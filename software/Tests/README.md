# MSXPi tests

Regression tests for the disk driver, the transfer code and PCOPY. They exist
because every one of these areas has broken in ways that only showed up on a
real machine or under Nextor; each test pins one of those failures down.

Run from WSL (Ubuntu). Emulator tests need the MSXPi-enabled openMSX in
`/opt/openMSX` and a free port 5000 (stop any running `msxpi-server.py`).

## Unit tests (seconds, no emulator)

| Test | Checks | Run |
|---|---|---|
| `test_disk_copy_z80.py` | DSKIO sector loops on an emulated Z80 against the real ROM: direct transfers outside page 1, XFER staging in page 1, failure when XFER is missing, failed sectors, /WAIT burst requests and the burst routines (incl. a trashed AF'), hex parser | `python3 test_disk_copy_z80.py ../target/msxpibios.rom ../zout/msx-dos.lst` |
| `test_payload_z80.py` | Generated transfer code (`../asm-common/transport`) in both ASM and C form; needs `libz80ex-dev`, SDCC | `python3 test_payload_z80.py` |
| `test_native_gpio.py` | Pi-side native/burst engine behaves exactly like the Python path, incl. fault injection | `python3 test_native_gpio.py` |
| `test_pcopy_receive.py` | PCOPY never writes a failed block to disk; needs a host C compiler | `python3 test_pcopy_receive.py` |
| `test_netreset.py` | `p netreset` rebuilds the Pi's TCP/IP setup and reopens the TAP: screen-sized reply, reasons for failure, teardown failure does not stop the rebuild | `python3 test_netreset.py` |
| `test_wifi_report.py` | `p wifi` names every interface whatever its index (msxpi0 climbs past 4 as the TAP is rebuilt), one 40-column line each | `python3 test_wifi_report.py` |
| `native_gpio_test.c` | C model of the CPLD edge contract for `native/gpio_transfer.c` | see `../Server/Python/src/native/README.md` |

## Emulator tests (minutes, openMSX + a private server instance)

**`nextor_mfr_copy.py`**: MegaFlashROM SCC+ SD + MSXPi under Nextor, COPY
SD <-> MSXPi, both results checked byte for byte. Covers the "Not a DOS disk"
(GETDPB) and "Bad file allocation table" (sector staging) bugs. Needs an MBR
image with a FAT12 first partition for the SD card (`--sd`).

```sh
python3 nextor_mfr_copy.py /tmp/t --sd nextor-mbr.dsk                    # FS-A1WSX, SD=B:, MSXPi=D:
python3 nextor_mfr_copy.py /tmp/t --sd nextor-mbr.dsk --machine Canon_V-25 \
    --pre "MAPDRV B: U" --pre "MAPDRV A: 1 2" --sd-drive A --pi-drive D     # MAPDRV layout
python3 nextor_mfr_copy.py /tmp/t --sd nextor-mbr.dsk --machine Canon_V-25 --no-mfr \
    --extra p1test/P1TEST.COM --pre P1TEST --no-copy                       # MSXPi DOS1 + P1TEST
```

`--rom` tests another ROM, `--trace` logs every DSKIO/DSKCHG/GETDPB call,
`--gui` shows the window, `--tcl FILE` adds breakpoints or other Tcl,
`--fault-burst-write` corrupts the checksum of the first /WAIT burst write
(its retry must go byte by byte). Exit code 0 = pass. The server log says
whether /WAIT bursts were used ("burst payloads - enabled" for reads,
"receiving them" for writes).

**`pcopy_emulator.py`** / **`verify_disk_copy.py`**: PCOPY download/upload
(with checksum-fault injection) and a FAT12 file check; see `README-pcopy.md`.

## Test programs for the MSX

**`p1test/P1TEST.COM`**: 40 KB self-checking program for disk transfers into
page 1 (4000-7FFF). It verifies its own loaded image; on DOS 2 it also writes
and reads back 16 KB at 4000 ten times. Prints PASS or the first bad address.
Useful on real hardware: copy it to an MSXPi drive and run it. Page-1
transfers only reach the driver under MSXPi's own DOS1 (Nextor remaps them).
Rebuild with `python3 p1test/build.py`.

## Notes

`PERFORMANCE-HANDOFF.md` and `PERFORMANCE-RESULTS-R2.md` record the 1.6
performance work, the Nextor COPY investigation and timings.
