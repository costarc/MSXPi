# Shared MSX payload engine

`payload.z80` is the source of truth for the C and ASM file/disk payload loops.
Run `python3 software/asm-common/transport/generate.py` after editing it. Generated files
are checked in; `--check` and both client build scripts reject stale output.
The C build uses an SDCC ABI-0 stack adapter, while ASM callers pass DE=buffer,
BC=count and HL=running 16-bit checksum. IX/IY and alternate registers survive.
Zero bytes perform no I/O. Carry on return reports cancellation; successful
bytes alone update the pointer/count/checksum. Public BIOS APIs are unchanged.

There is one receive loop: request a transfer, then wait for status zero. openMSX
emulates the CPLD at port level, so the MSX side has no emulator path. Checksum
folding, headers, index checking, retries and disk commit decisions remain in
the protocol layer. The disk driver stages each sector in a private 512-byte driver buffer,
then uses LDIR or the DOS XFER helper to copy the entire sector across RAM slot
boundaries. The kernel's shared SECBUF is never used as scratch, since another
disk kernel may retain filesystem metadata there. BASIC/early boot retain RDSLT/WRSLT when XFER is unavailable. Failed
receive sectors are never copied to the caller. The old SEND_P1 workarea byte
is reserved; its offset is unchanged. PCOPY uses 8192-byte blocks in both
directions, so comparisons no longer mix block size with transfer direction.

Polling is intentionally still used for file/disk payloads. UNAPI ETH_END
leaves /WAIT off, and the existing link claim/disk busy guard prevents network
transactions from interleaving. The payload kernel does not acquire the link
itself: callers must hold it over the entire command/response, not each block.
ESC is sampled at most 256 completed bytes apart and during busy polling. The
shared helper preserves PPI upper bits, keyboard row selection and IFF state.
The existing C header-byte primitives are unchanged.

The DOS ROM uses three pre-existing alignment holes for generated TX, wait,
and ESC code. Their DEFS expressions enforce capacity; GETSLT/GETWRK and the
UNAPI placement assertions remain active. The full ROM fits without moving
these entry points or removing features. Standalone ASM clients include the
same code contiguously. Assembly was checked with zmac and sjasmplus.

Networking has a specialized bounded, keyboard-free TX checksum loop. It
keeps the sum in E and calls readiness directly instead of the single-byte
wrapper. Its protocol/checksum differs from the file protocol, so it does not
call the foreground payload kernel. Existing UNAPI /WAIT receive bursts now
use the native Pi engine when enabled; READY stays high for the entire burst,
including across the 256-byte boundaries used by ordinary payload calls. A
GPIO backend unable to hold READY now fails instead of silently substituting
unsafe per-byte transfers.

No CPLD register, wire protocol, or openMSX device change is introduced. A fresh
Quartus 13.0sp1 build of the current CPLD used 46/64 macrocells. Its timing
constraints are incomplete; a successful fit is not proof of a new timing
margin. General file/disk INIR/OTIR bursts and CPLD prefetch/mailbox changes are
not enabled by this revision. Their need should be decided from hardware
measurements of this common software bottleneck removal.

## Verification

The tests below live in `software/Tests/`, which is **not part of the release
branch** - it is carried on the development branches (`performance` and the
feature branches cut from it). Check one of those out to run them.

- `python3 software/Tests/test_payload_z80.py`: executes assembled SDCC output
  with libz80ex. RX/TX and ABI checks cover hardware/TCP status, lengths
  0/1/255/256/257/512/8192, checksum overflow, register preservation, IFF on/off,
  delayed readiness and ESC both busy and ready. Network TX tests cover frame
  sizes through 1514, checksum, bounded timeout and absence of keyboard scans.
- `python3 software/Tests/test_native_gpio.py`: protocol framing/retries,
  native failure behavior, burst selection and wrapper boundaries.
- `cc -std=c11 -O2 -Wall -Wextra -Werror -fsanitize=undefined software/Tests/native_gpio_test.c -o /tmp/msxpi-native-test`
  followed by `/tmp/msxpi-native-test`: GPIO edge/byte model including continuous
  READY bursts and a timeout after partial completion.
- `python3 software/Tests/test_pcopy_receive.py`: rejects failed receive data
  before a disk write.
- `python3 software/Server/Python/src/test_msxpi_eth.py`: shuttle regression suite.
- `software/Tests/pcopy_emulator.py`: full copy/upload against isolated served
  disks. See its `--direction` and `--fault` options; use an MSXPi-enabled openMSX.

The Linux pcopy, p and templatc clients build. The unchanged msxarch.c source
has malformed literals and triggers an SDCC internal compiler error; this
revision does not repair that separate application. Windows SDCC 4.0 and Linux
SDCC 4.2 ABI-0 PCOPY builds were both exercised in openMSX.
