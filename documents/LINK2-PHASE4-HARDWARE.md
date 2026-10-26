# LINK2 phase 4 - hardware test procedure (Canon V-25 + Pi, v1.6 CPLD)

Branch `feature/link2` (pushed, head aaaaba91). Results go into LINK2-TEST-PLAN.md ("Phase 4"). What is
here is T6 steps 1 to 4 and 6 (Ethernet, step 5, and the DOS half, step 7, come after).

Not available yet, so not in this procedure: LINK2T.BAS (the full CALL MSXPI suite), the legacy-style
no-GO control burst, polled L2TEST sends. Say if you want them built.

## 1. Pi: bring the server to the branch

On the Pi (or from MSX-DOS with the legacy ROM still in the EEPROM):

    msxpiupd feature/link2

Check the server log shows BuildId 20261026.082 or later, and that `msxpi.ini` is kept. The server
speaks both protocols, so the old ROM keeps working until you flash.

Files that matter (from `software/target/`): `msxpi32k.rom` (32768 bytes), `msxpiext.bin` (3345),
`L2TEST.BIN` (2570; the server sends it, `l2test bin`, from MSXPI_HOME as `l2test.bin`).
Confirm `l2test.bin` exists in MSXPI_HOME (lower case on the Pi); if not, copy `L2TEST.BIN` there.

## 2. Flash the EEPROM

`at28c256` with `msxpi32k.rom`, the full 32 KB, A15 jumper as in your usual flashing (the chip has
no address decode: the other half shows at 8000h). Keep a copy of the current image first.

Jumper: the DOS half (legacy protocol) boots with a disk system; the BIOS half (LINK2) is the
BIOS-only bank (BANK1 in openMSX). The Canon has no drive, so it always runs the BIOS half = LINK2.

## 3. Functional (T6.2)

Power on the Canon, with the server running and logging (`tail -f` the log, level info).

    CALL MSXPIVER

Expect the version line with the new ROM version, no error. Then:

    CALL MSXPI("0,pwd")
    CALL MSXPI("0,ls")
    CALL MSXPI("1,date")
    CLEAR 200,&HBFFF
    CALL MSXPI("2,D000,l2test pat 512 7")
    PRINT HEX$(PEEK(&HD000)),HEX$(PEEK(&HD001)),HEX$(PEEK(&HD1FF))

Pass: no "?" errors, no hangs. The pattern byte i is i*13 + (i>>8)*7 + seed, so with seed 7 the first
bytes are 07, 14, 21 (hex) and byte 511 is `(511*13 + 7 + 7) AND 255`. Also try a big one:

    CALL MSXPI("2,A000,l2test pat 8192 7")
    CALL MSXPI("2,A000,l2test pat 32768 7")   : REM overwrites the BASIC area; BASIC may need NEW after

(the 32 KB one needs a page 2/3 buffer; if BASIC complains, skip it and say so). Server log should show
LINK2 transfers with no retries on a healthy link.

## 4. READY race: bursts with OTIR (T6.3), the case that failed before

    10 CLEAR 200,&HBFFF
    20 CALL MSXPI("2,C000,l2test bin")
    30 DEFUSR=&HC003
    40 C$="l2test sink 512 7"+CHR$(0)
    50 FOR I=1 TO LEN(C$):POKE &HE000+I-1,ASC(MID$(C$,I,1)):NEXT
    60 POKE &HE040,0:POKE &HE041,2           : REM N = 512
    70 POKE &HE042,7                          : REM seed
    80 POKE &HE044,0:POKE &HE045,&HD0         : REM buffer D000h: >= 8000h, so it bursts
    90 POKE &HE046,&HE8:POKE &HE047,3        : REM 1000 repetitions
    100 A=USR(0)
    RUN

It prints `L2T OK=xxxx F=xxxx T=xxxx` (hex). 1000 = 03E8.

Pass: `OK=03E8 F=0000`, and the server log has 1000 "l2test sink" lines that verify. Record T (jiffies:
1/60 s NTSC, 1/50 s PAL) and the retry/abort counts in the log. Run a first smoke with 10 repetitions
(`POKE &HE046,10:POKE &HE047,0`) before the 1000.

Also run N = 4096 (`POKE &HE040,0:POKE &HE041,&H10`, 100 reps); the buffer D000h..DFFFh is the limit
before the parameters at E000h.

## 5. Speed (T6.4)

KB/s = (N x reps) / 1024 / (T / jiffies per second). Take it for L2TEST 512 x 1000 and 4096 x 100.
For CALL MSXPI, time a `l2test pat 8192 7` download with `TIME` (BASIC jiffy clock) around a loop of 20
and compare with the T0 hardware baseline in LINK2-TEST-PLAN.md (the legacy ROM on the same Canon: flash
back if you have no number). Expected: CALL MSXPI no slower, bursts much faster than polled.

## 6. Soak (T6.6)

Loop the program of section 4 (reps 1000, GOTO the CALL line) and a CALL MSXPI download for 2 hours,
log open. Count F and the server log's retries and aborts. Expect 0 F, 0 aborts.

## What to send back

- Section 3: any error text, hangs, the PEEK values.
- Section 4: the `L2T OK/F/T` lines and the server log excerpt for any failure (first error with
  timestamps).
- Section 5: the T values, KB/s.
- Whether `CALL MSXPIVER` shows the new ROM build.

If the Canon hangs at power on: reflash the previous image, and tell me; the legacy ROM + the new server
works (phase 1).
