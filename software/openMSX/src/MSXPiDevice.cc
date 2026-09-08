#include "MSXPiDevice.hh"
#include "MSXCPU.hh"
#include "Timer.hh"
#include <chrono>
#include "xrange.hh"
#include <algorithm>
#include <array>
#include <vector>

namespace openmsx {

MSXPiDevice::MSXPiDevice(const DeviceConfig& config)
	: MSXDevice(config)
	, waitCycles(unsigned(config.getChildDataAsInt("wait_cycles", 0)))
	, rdyFailEvery(unsigned(config.getChildDataAsInt("rdy_fail_every", 0)))
{
	thread = std::thread(&MSXPiDevice::readLoop, this);
	reset(EmuTime::dummy());
}

MSXPiDevice::~MSXPiDevice()
{
	shouldStop = true;
	close();
	// poller.abort() below unblocks poll(), but nothing wakes a condition
	// variable - without these, join() waits on a parked thread.
	rxCv.notify_all();
	rxSpaceCv.notify_all();
	if (thread.joinable()) {
		poller.abort();
		thread.join();
	}
}

void MSXPiDevice::close()
{
	auto oldSock = sock.exchange(OPENMSX_INVALID_SOCKET);
	if (oldSock != OPENMSX_INVALID_SOCKET) {
		sock_close(oldSock);
	}
}

void MSXPiDevice::reset(EmuTime /*time*/)
{
	std::lock_guard lock(mtx);
	rxQueue.clear();
	readRequested = false;
	waitMode = false;
	rxSpaceCv.notify_one(); // a machine reset frees the whole queue
}

byte MSXPiDevice::readIO(uint16_t port, EmuTime time)
{
	switch (port & 0xff) {
	case 0x56: // Status
	case 0x57: // Version
		return peekIO(port, time);
	case 0x5A: // Data
		if (waitMode) {
			// Hardware /WAIT: the read itself starts the transfer and
			// stalls the Z80 until the byte is available.  Blocking the
			// emulation thread here IS the stall - that is exactly what
			// the real CPLD does to the CPU.
			//
			// The wait is bounded so that a dead or absent server cannot
			// freeze openMSX.  Real hardware degrades the same way: with
			// SPI_RDY low the CPLD never starts a transfer, never
			// asserts /WAIT, and the read returns a stale byte.
			// NOT named WAIT_TIMEOUT: that is a Win32 macro (258L from
			// winbase.h) and the name would silently expand to a constant.
			// Charge the guest for the stall.  This is the idiomatic
			// openMSX way to model wait states (MSXCPU::waitCyclesZ80,
			// as used by VDP.cc and TurboRFDC.cc) and it advances
			// EMULATED time, which blocking this thread does not.
			//
			// It cannot replace the block below: waitCycles takes a
			// count known in advance, whereas the byte itself arrives
			// from a socket whenever the server gets round to it.
			if (waitCycles > 0) {
				time = getCPU().waitCyclesZ80(time, waitCycles);
			}

			// Fault injection: emulate RPI_READY being low for this read.
			if (rdyFailEvery && (++rdyCounter % rdyFailEvery) == 0) {
				return 0xff; // stale bus, exactly as hardware does
			}

			static constexpr auto RX_STALL_TIMEOUT = std::chrono::milliseconds(250);
			std::unique_lock lock(mtx);
			readRequested = false;
			if (rxQueue.empty()) {
				rxCv.wait_for(lock, RX_STALL_TIMEOUT, [&] {
					return !rxQueue.empty() || shouldStop.load();
				});
			}
			if (!rxQueue.empty()) {
				auto b = rxQueue.pop_front();
				rxSpaceCv.notify_one(); // room for the reader thread
				return b;
			}
			return 0xff;
		}
		if (readRequested) {
			readRequested = false;
			std::lock_guard lock(mtx);
			if (!rxQueue.empty()) {
				auto b = rxQueue.pop_front();
				rxSpaceCv.notify_one(); // room for the reader thread
				return b;
			}
		}
		return 0xff; // No data ready
	default:
		return 0xff;
	}
}

byte MSXPiDevice::peekIO(uint16_t port, EmuTime /*time*/) const
{
	switch (port & 0xff) {
	case 0x56: // status
		if (sock == OPENMSX_INVALID_SOCKET) {
			return 0x01; // server not available
		}
		{
			std::lock_guard lock(mtx);
			if (!rxQueue.empty()) return 0x02; // byte available
		}
		return 0x00;
	case 0x57: // Version + wait-mode read-back
		// This port has to answer TWO questions at once: "is wait mode on?"
		// and "am I openMSX or real hardware?".  msxpi_bios.asm:97 asks the
		// second one on EVERY BYTE:
		//
		//     in a,($57) / cp $FE / jr c,physical_path
		//
		// so anything below $FE means "real hardware" to every existing
		// binary.  Real CPLD v1.6 answers $0E and $8E; returning $8E here
		// would therefore make stock MSXPi code take the physical-hardware
		// path under emulation and read stale bytes.
		//
		// Hence $FE / $FF rather than $0E / $8E: both stay at or above $FE,
		// so openMSX keeps identifying itself correctly in both states,
		// while bit 0 still reports the mode.  Real hardware can never
		// collide with these - the CPLD pins bit 6 low, capping $57 at $BF.
		return waitMode ? 0xFF : 0xFE;
	case 0x5A: // data
		if (readRequested) {
			std::lock_guard lock(mtx);
			if (!rxQueue.empty()) {
				return rxQueue.front();
			}
		}
		return 0xff;
	default:
		return 0xff;
	}
}

void MSXPiDevice::writeIO(uint16_t port, byte value, EmuTime time)
{
	switch (port & 0xff) {
	case 0x56: // control
		if (value == 0xFF) {
			reset(time); // also clears waitMode, as the CPLD does
			break;
		}
		if (sock != OPENMSX_INVALID_SOCKET) {
			readRequested = true;
		}
		break;
	case 0x57: // wait-mode register (CPLD v1.6)
		// Only $01 sets it and only $00 clears it; every other value is a
		// no-op, matching the CPLD's mode_reg process.
		if (value == 0x01) {
			std::lock_guard lock(mtx);
			waitMode = true;
		} else if (value == 0x00) {
			std::lock_guard lock(mtx);
			waitMode = false;
		}
		break;
	case 0x5A: // data
		// A write stalls the Z80 on real hardware exactly as a read does
		// (the CPLD asserts /WAIT on spi_en, which a write also sets).
		if (waitMode && waitCycles > 0) {
			time = getCPU().waitCyclesZ80(time, waitCycles);
		}
		if (sock != OPENMSX_INVALID_SOCKET) {
			auto res = sock_send(sock, reinterpret_cast<const char*>(&value), 1);
			(void)res; // ignore error
		}
		break;
	default:
		break;
	}
}

void MSXPiDevice::readLoop()
{
	// 64 KB: at or above the usual socket receive buffer, so a burst is taken
	// in about one syscall.  Allocated once here rather than per iteration,
	// and on the heap rather than the stack - a buffer this size is not
	// something to put on a thread stack.
	//
	// MAX_QUEUE_SIZE is deliberately far larger than any single block: the
	// queue only ever grows to what is actually used (cb_queue starts at zero
	// capacity and doubles), so the ceiling costs nothing until a transfer
	// needs it.  With the wait above it is a throughput knob, not a
	// correctness limit - too small merely stalls, it no longer loses data.
	static constexpr size_t MAX_QUEUE_SIZE = 64 * 1024;
	std::vector<char> buf(64 * 1024);

	while (!shouldStop) {
		if (sock == OPENMSX_INVALID_SOCKET) {
			sock = socket(AF_INET, SOCK_STREAM, 0);
			if (sock == OPENMSX_INVALID_SOCKET) {
				Timer::sleep(1'000'000); // retry once per second
				continue;
			}

			sockaddr_in addr{};
			addr.sin_family = AF_INET;
			addr.sin_port = htons(5000);
			addr.sin_addr.s_addr =
			        htonl(INADDR_LOOPBACK); // 127.0.0.1
			if (connect(sock, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
				close();
				Timer::sleep(1'000'000); // retry once per second
				continue;
			}
		}

#ifndef _WIN32
		if (poller.poll(sock)) {
			continue; // error or abort
		}
#endif
		// Wait for room BEFORE reading, rather than reading and discarding
		// what will not fit.  The old code capped the queue at 16 KB and threw
		// the rest away - "skip excess bytes" - which meant the device silently
		// lied about what it had received: the server had sent the bytes, the
		// MSX never saw them, and nothing anywhere reported an error.  A block
		// of 16384 plus its 4-byte header and checksum came to 16389, five over
		// the cap, so every large pcopy download lost its tail - including the
		// checksum byte the MSX then waited for for ever.
		//
		// Not reading is all that is needed: the socket buffer fills, TCP
		// closes its window, and the server's sendall() blocks until the MSX
		// catches up.  That is also how real hardware behaves, where the GPIO
		// transport is synchronous and the server can never run ahead.
		//
		// wait_for rather than wait, matching RX_STALL_TIMEOUT in readIO: a
		// missed notify then costs a few milliseconds instead of parking this
		// thread for ever.  It also guarantees the loop re-checks shouldStop,
		// so the destructor's join() cannot hang - poller.abort() unblocks
		// poll(), but nothing wakes a condition_variable.
		// Read only as much as will fit.  Waiting for room for a WHOLE buffer
		// would idle the reader whenever the queue held anything at all, since
		// the buffer is the same size as the cap; asking for the free space
		// keeps it working while still never overflowing.
		size_t room;
		{
			static constexpr auto RX_SPACE_TIMEOUT = std::chrono::milliseconds(5);
			std::unique_lock lock(mtx);
			rxSpaceCv.wait_for(lock, RX_SPACE_TIMEOUT, [&] {
				return shouldStop.load() || rxQueue.size() < MAX_QUEUE_SIZE;
			});
			if (shouldStop) break;
			room = MAX_QUEUE_SIZE - std::min(rxQueue.size(), MAX_QUEUE_SIZE);
			if (room == 0) {
				continue; // still full - let the MSX drain, try again
			}
		}

		auto n = sock_recv(sock, buf.data(), std::min(buf.size(), room));
		if (n < 0) { // error
			close();
			continue;
		}
		std::lock_guard lock(mtx);
		for (auto i : xrange(size_t(n))) {
			rxQueue.push_back(buf[i]);
		}
		rxCv.notify_one(); // release a wait-mode read blocked in readIO
	}
}

REGISTER_MSXDEVICE(MSXPiDevice, "MSXPiDevice");

} // namespace openmsx
