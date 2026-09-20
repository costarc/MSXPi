# PCOPY regressions

`python3 software/Tests/test_pcopy_receive.py` compiles the real PCOPY control flow with host-side transport and disk stubs. It verifies that failed receives never reach `fcb_write`, while valid intermediate and final blocks are written. Requires a host C compiler (`CC`, default `cc`).

`software/make.sh pcopy OUTPUT_DIRECTORY` builds the client with Linux SDCC. The existing Fusion-C library uses ABI 0, so the script selects `--sdcccall 0` and links an ABI-0 standard library. By default this is the installed Windows SDCC 4.0 `C:/Apps/SDCC/lib/z80/z80.lib`; override `SDCC_ABI0_LIB` if needed. The compiler and assembler execute under Linux. Requires `sdcc`, `sdar`, and GNU `objcopy`. It does not deploy disks.

The end-to-end test uses a custom MSXPi-enabled openMSX, Python server dependencies, and bootable MSXPi disk images:

```sh
python3 software/Tests/pcopy_emulator.py \
  --rom /absolute/path/msxpibios.rom \
  --client /absolute/path/pcopy.com \
  --input /absolute/path/ALESTE.ROM \
  --output /absolute/path/test-output \
  --fault once
```

Fault modes:

- `none`: successful copy and subsequent DIR, with exact destination-byte verification.
- `once`: one checksum mismatch in a disk write; the copy must recover and match the input.
- `always`: every attempt at the first disk-write block fails; exactly three attempts and a DOS disk-error prompt are required.
- `sector-info`: sector-info transmission fails; exactly three attempts, a DOS error, and no subsequent sector-write command are required.

The test copies the two disk images and input file, supplies a private configuration/ROM extension, and injects faults into a private copy of the server source. It stops its own server immediately after each run. Port 5000 must be free. Defaults for the two source images are `/home/pi/msxpi/disks/msxpiboot.dsk` and `/home/pi/msxpi/disks/tools.dsk`; override `--boot-disk` and `--data-disk` as needed. The machine is Panasonic_FS-A1WSX with ram4mb and the MSXPi extension. Tests invoke PCOPY directly rather than relying on a `P COPY` alias.

These are protocol and filesystem-integrity tests. They do not simulate Raspberry Pi GPIO timing or establish physical /WAIT safety or transfer performance.

`--direction upload` verifies MSX-to-Pi copying from an isolated B: image and
compares the resulting host file byte-for-byte. Fault modes currently apply
only to downloads.

`verify_disk_copy.py image.dsk PERF.ROM reference.rom` compares an MSX image
file directly with its host reference. Stop writes to the image before reading
it for verification.

## Sector staging regression

Run `python3 software/Tests/test_disk_copy_z80.py ROM LISTING` against the zmac
ROM and symbol listing. It executes the actual sector-copy dispatcher and
BASIC fallback across page-1 boundaries in both directions, with DOS slot
helpers modeled at their entry points. It also checks the compact ROM hex
parser. `pcopy_emulator.py --direction dos-copy` checks the real DOS COPY and
XFER implementations using a full file; its timeout allows two disk transfers
per byte. PCOPY uses 8192-byte blocks in both directions.


For cross-controller coverage, `pcopy_emulator.py --direction dos-copy
--nextor-hd IMAGE` uses Sunrise IDE/Nextor 2.10 in slot 1, MSXPi in slot 2,
and a Philips NMS 8245 with 128 KiB RAM. IMAGE must contain a standard MBR
and a first FAT12 partition bootable into Nextor (NEXTOR.SYS and COMMAND2.COM,
without an AUTOEXEC that launches another program). The test clones IMAGE,
injects INPUT.ROM offline, copies A:INPUT.ROM to C:OUTPUT.ROM on MSXPi, then
copies it back to A:ROUND.ROM. It compares both files byte-for-byte. C: maps
to MSXPi unit 0 in this setup; D: is the built-in floppy, unlike the user's
MFR drive layout. This is a separate-kernel regression, not an emulation of
MFR's SD controller. The locally installed Nextor emulator ROM path is
specified in the harness. No installed image is modified.

The disk-loop execution test also checks one- and two-sector read/write
requests, preservation of the kernel shared sector buffer, and refusal to
copy rejected read data into the caller's buffer.
