# Performance branch checkpoint — 2026-09-10

## UPDATE 2026-09-11: Nextor COPY regression root-caused and fixed

Reproduced in openMSX with the user's topology (Panasonic_FS-A1WSX,
MegaFlashROM_SCC+_SD in slot 1 with a FAT SD image, MSXPi in slot 2, Nextor
booting from the MFR flash; in the emulator the SD auto-maps to B:).
`COPY D:ALESTE.ROM B:ROUND.ROM` gave "Not a DOS disk reading drive D:".

Cause: DSKCHG always returns "unknown", so when Nextor's media-check timer
lapses mid-copy it re-reads the boot sector (DSKIO returned it correctly) and
then calls GETDPB with CARRY SET. GETDPB was a bare RET, returning that carry,
which Nextor treats as failure. Timing-dependent, hence intermittent: the
pre-staging R1 ROM (a5cef7c) also failed in one of two runs. The R2/R2.1
staging/XFER/private-buffer changes were not the cause.

Fix: GETDPB = `xor a / ret` (DPB untouched as before; the DOS1 kernel's only
call site ignores A and flags). Verified: both COPY directions between the
MFR SD and MSXPi byte-identical (SHA256 42a0470e...), with Nextor calling
GETDPB 4-5 times during the copy. The DOS1-only boot was not re-run.

The sections below describe the state BEFORE this fix.

## Status: work in progress, Nextor regression unresolved

This checkpoint was requested before the user's daily quota expires. Do not
interpret the commit as a release or as a confirmed fix for the COPY errors.
All generated transport sources, native engine sources, clients, ROM and boot
image currently in the branch are included. Do not lose the working tree or
revert to the original baseline when resuming.

## User hardware and exact failure

- Raspberry Pi Zero 2 W; CPLD v1.6 with /WAIT.
- Manuel Pazos MegaFlashROM SCC+ SD with 512 KiB mapper in slot 1.
- MSXPi in slot 2, assigned C: and D:. D: is msxpitools.dsk.
- Nextor v2.10 by Konamiman; MFR initially assigns its flash to A:.
- User runs `MAPDRV A: 1 2` to map A: to the SD card.
- `COPY A:ALESTE.ROM D:` repeatedly reports "Not a disk reading drive D:"
  after copying. Retry repeats the error. DIR shows 262144 bytes but this
  does not prove the data is correct. One attempt succeeded: intermittent.
- `COPY D:ALESTE.ROM A:ROUND.ROM` reported "File allocation error" and did
  not create the destination. MSXPi-to-MSXPi COPY works.
- Latest: user reproduced the error on another Nextor/SD project without
  MAPDRV. Therefore this is NOT specific to MFR or to MAPDRV.
- All earlier MSXPI-DRIVER versions could copy across devices. User explicitly
  wants troubleshooting/testing until resolved. Do not ask them to accept
  the regression in exchange for speed.

## Implemented performance work

- Canonical software/transport/payload.z80 generates synchronized C inline
  assembly and ASM includes. Fast payload loops preserve checksum/retry
  semantics, choose GPIO/TCP once and reduce readiness/keyboard overhead.
- Native optional Pi GPIO payload and existing UNAPI burst engines, Python
  wrapper and atomic build.sh with symbol validation; no CPLD wire changes.
- UNAPI TX checksum/readiness loop improvement.
- PCOPY uses a single 8192-byte constant for BOTH upload/download.
- R2 introduced per-sector staging plus LDIR / kernel XFER for page-1 copies,
  eliminating the old per-byte RDSLT write branch. Compact STRTOHEX recovers
  ROM space; fixed entry points and UNAPI placement assertions still hold.
- R2.1 changed staging from shared SECBUF to a private buffer appended after
  UNAPI_WRKEND in the disk work area (MYSIZE = UNAPI_WRKEND + 512).
  This is only a candidate buffer-isolation correction. User reports the
  cross-device failure persists. DO NOT call the regression fixed.
- Target ROM and boot image currently contain R2.1. Boot image includes
  P.COM, PCOPY.COM and MSXPIBIO.ROM. Clients remain the R2 8 KiB builds.

## Tests and important limitations

- R2.1 assembled with zmac; fixed ROM bounds/entry assertions pass.
- test_disk_copy_z80.py executes ROM sector-copy helpers across page-1
  boundaries (44 cases), all 65536 hex-parser values, and one/two-sector
  read/write/error loops. Private-buffer isolation and rejected-read checks
  pass. These unit tests do NOT reproduce the reported hardware failure.
- R2.1 full MSXPi boot: 262144-byte PCOPY download with exactly one injected
  checksum error passes byte-for-byte (139.9 s including harness).
- R2.1 full Nextor 2.10/Sunrise IDE in slot 1, MSXPi slot 2, Philips NMS8245
  internal 128 KiB mapper: COPY to MSXPi and back passes both hashes (243.5 s).
- Old R2 ALSO passes the Sunrise cross-controller file comparisons. A final
  DIR pagination timeout was a harness issue, corrected to list one filename.
- In this Sunrise setup MSXPi is C: (unit 0); D: is the internal floppy.
  Early "Not ready D:" attempts were NOT reproductions of the reported bug.
- Actual MFR emulator attempts did not reach usable DOS with available test
  media. Do NOT claim MFR coverage. Installed firmware exists as
  /opt/openMSX/share/systemroms/extensions/mfrsd.rom.gz, decompressed SHA1
  1621f623b834dc57cb2983f30b36bcc3ac56cafd, 8208384 bytes. The emulator supplies
  the 512 KiB mapper in subslot 2 and SD kernel in subslot 3.
- Current new --nextor-mapper diagnostic option combines Sunrise ROM at 1-3
  and 512 KiB RAM at 1-2. The first run booted DOS1 instead of Nextor and
  failed; it is NOT a passing regression configuration. Investigate startup
  or use a different topology. Do not confuse that failure with the user's.
- No CPLD or MSXPiDevice changes have been needed so far. Any future CPLD
  change MUST have a corresponding openMSX device change per user instruction.

## Performance data

See PERFORMANCE-RESULTS-R2.md. User explicitly supplied NO timing values for
failed COPY tests; keep them separate from timed PCOPY results. Native-on
MSXPi-disk PCOPY now measures 50.50 s download / 52.50 s upload versus R1's
67.04 / 106.03 s (~33% / 102% higher throughput). Upload also changed from
16 KiB to 8 KiB; do not attribute all its gain to the driver alone.

## Workspace/toolchain and resume points

Repository: /mnt/c/Users/roniv/Dev/github/MSXPi, branch performance.
Scratch and deliverables: /mnt/c/Users/roniv/Documents/Codex/2026-09-08/fix-x20.
- work/perf-r2 contains R1 source backups (msxpi-driver.mac and msxpi_bios.asm),
  R2 ROM, Windows/Linux clients and assembly listings.
- work/perf-r2-fix contains R2.1 ROM/listing, fixed-nextor and fixed-dos1 logs,
  Nextor MBR image, failed MFR startup experiments and experimental harness.
- work/regression-nextor/mapper-r21 contains the latest diagnostic failure.
- outputs/MSX-performance-r2.1.zip is the candidate package already sent.
- Original source file /mnt/c/tmp/ALESTE.ROM is 262144 bytes, SHA256
  42a0470e9ff22881039e4fdfdbed3b3348c07fb3a7a21591cca49a93d85d977e.
- Latest full profile attachment:
  /mnt/c/Users/roniv/.codex/attachments/2da37a57-bcd0-4bb4-b50b-41fe24842e43/pasted-text.txt.
  It is large: parse/filter it rather than dumping it into the conversation.
- Linux client build: bash software/make.sh pcopy OUTPUT_DIR. Linux SDCC4.2
  must use ABI0 plus Windows ABI0 runtime (script handles this).
- Windows SDCC4.0: /mnt/c/Apps/SDCC/bin/sdcc.exe and sdar.exe.
- zmac: /mnt/c/Users/roniv/Dev/zmac/zmac.exe, --oo hex,lst, Windows paths for
  --od and include paths software/asm-common/include and ROM/src/MSX-DOS.
  objcopy -I ihex -O binary --gap-fill 0xff converts the assembled hex.
- Native openMSX: /opt/openMSX/bin/openmsx. Run isolated test servers/disks;
  port 5000 cannot be shared. Terminate only test-owned processes.
- Preserve CRLF files; git diff --check needs cr-at-eol whitespace setting.

Continue with a controlled comparison against the pre-staging disk driver,
and examine Nextor's mapper/slot and buffer contracts. The previous shared-
buffer hypothesis was not proven. Avoid another claimed fix based solely on
Sunrise/internal-RAM passes. Keep the significant speed gains where correctness
can be established, but prioritize restoring cross-device correctness.
