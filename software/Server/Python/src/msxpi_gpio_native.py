# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

"""Optional native GPIO payload engine; Python owns pin setup and cleanup."""
import ctypes as C
import os
from pathlib import Path
import time


class NativeGPIO:
    def __init__(self, registers, masks):
        self.registers = registers  # keep the ctypes view/mmap alive
        self.masks = (C.c_uint32 * 5)(*masks)
        self.half_period_ns = int(os.environ.get('MSXPI_GPIO_HALF_PERIOD_NS', '250'))
        self.timeout_ms = int(os.environ.get('MSXPI_GPIO_TIMEOUT_MS', '1000'))
        if not 250 <= self.half_period_ns <= 100000:
            raise ValueError('MSXPI_GPIO_HALF_PERIOD_NS must be 250..100000')
        if not 1 <= self.timeout_ms <= 60000:
            raise ValueError('MSXPI_GPIO_TIMEOUT_MS must be 1..60000')
        self.library = C.CDLL(str(Path(__file__).parent/'native/libmsxpi_gpio.so'))
        self.transfer = self.library.msxpi_gpio_transfer
        self.transfer.argtypes = [C.POINTER(C.c_uint32), C.POINTER(C.c_uint32),
                                  C.POINTER(C.c_uint8), C.POINTER(C.c_uint8), C.c_size_t,
                                  C.c_uint32, C.c_uint32, C.POINTER(C.c_size_t),
                                  C.POINTER(C.c_uint64)]
        self.transfer.restype = C.c_int
        self.burst = self.library.msxpi_gpio_burst
        self.burst.argtypes = self.transfer.argtypes
        self.burst.restype = C.c_int
        # Delay between CS low and the first clock edge; 0 keeps the original
        # timing.  The v0.8.2 board (PCB v0.7 Rev.7) needs one - see
        # msxpi_gpio_set_cs_setup() in native/gpio_transfer.c.  An older
        # library without the setter simply keeps its fixed timing.
        self.cs_setup_ns = int(os.environ.get('MSXPI_GPIO_CS_SETUP_NS', '0'))
        if not 0 <= self.cs_setup_ns <= 100000:
            raise ValueError('MSXPI_GPIO_CS_SETUP_NS must be 0..100000')
        if self.cs_setup_ns:
            setter = getattr(self.library, 'msxpi_gpio_set_cs_setup', None)
            if setter is None:
                raise ValueError('MSXPI_GPIO_CS_SETUP_NS needs a rebuilt '
                                 'native/libmsxpi_gpio.so (run native/build.sh)')
            setter.argtypes = [C.c_uint32]
            setter.restype = C.c_int
            setter(self.cs_setup_ns)
        self.bytes = self.wait_ns = self.elapsed_ns = 0

    def _transfer(self, payload, length, burst=False):
        result = bytearray()
        # Return to Python at least every 256 bytes to service signals. READY
        # still cycles per BYTE, exactly as the current polled BIOS expects.
        # Existing UNAPI bursts must never cross a Python return with READY
        # lowered. Keep a bounded whole burst inside C (Ethernet max is 1518).
        if burst and not 0 <= length <= 65535:
            raise ValueError('native burst length must be 0..65535')
        chunk = max(1, length) if burst else 256
        transfer = self.burst if burst else self.transfer
        for offset in range(0, length, chunk):
            count = min(chunk, length-offset)
            tx = None if payload is None else (C.c_uint8 * count).from_buffer_copy(payload[offset:offset+count])
            rx = (C.c_uint8 * count)() if payload is None else None
            done, wait = C.c_size_t(), C.c_uint64()
            start = time.monotonic_ns()
            rc = transfer(self.registers, self.masks, tx, rx, count,
                               self.half_period_ns, self.timeout_ms, C.byref(done), C.byref(wait))
            self.elapsed_ns += time.monotonic_ns()-start
            self.wait_ns += wait.value
            self.bytes += done.value
            if rc or done.value != count:
                # Never retry through Python after partial I/O: the peer is
                # already inside this block. Let the protocol report failure.
                raise OSError(f'native GPIO transfer failed rc={rc}, completed={offset+done.value}/{length}')
            if rx is not None:
                result.extend(rx)
        return result

    def read(self, length):
        return self._transfer(None, length)

    def write(self, payload):
        self._transfer(payload, len(payload))

    def write_burst(self, payload):
        self._transfer(payload, len(payload), burst=True)

    def read_burst(self, length):
        """Receive with READY held for the whole block (MSX OTIR in wait mode)."""
        return self._transfer(None, length, burst=True)

    def report(self):
        if self.bytes:
            print(f'[native GPIO] {self.bytes} payload bytes; '
                  f'{self.elapsed_ns/self.bytes/1000:.2f} us/byte in engine; '
                  f'{self.wait_ns/self.bytes/1000:.2f} us/byte waiting for MSX', flush=True)
