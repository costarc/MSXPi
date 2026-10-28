@echo off

REM Builds one MSX-DOS client (Client\src\<name>.c) with SDCC 4.6.0 in its own calling convention
REM (sdcccall 1): SDCC's own runtime, msxpi-bios.lib and fusion46.lib (tools\build_fusion46.py)
REM built here on every call. Usage: make.bat <name>
REM   KEEPMAP=1        also keep the linker map
REM   MAKE_OUTDIR=dir  put the .com (and the .map) there only, not in target\ and the shared FloppyA
sdcc --version | findstr /C:"4.6.0" >nul
IF ERRORLEVEL 1 (
    echo ERROR: SDCC 4.6.0 is required ^(sdcc --version must report 4.6.0^).
    EXIT /B 1
)

python asm-common\transport\generate.py --check
IF ERRORLEVEL 1 EXIT /B 1

SET BASEDIR=.
SET FLOPPYA=..\..\..\MSX\MSXPi\FloppyA
SET TARGETDIR=target
SET HEX2BINDIR="..\..\..\MSX\MSX-C\WorkingFolder\Tools\Hex2Bin\Hex2bin Windows"
SET HEX2BIN=%HEX2BINDIR%\hex2bin.exe 
SET INCLUDEDIR=..\..\..\MSX\MSX-C\WorkingFolder\fusion-c\include
SET MSXPILIB=C-common\lib
SET proga=Client\src\%1
SET sourcename=%1
REM The MSX-DOS startup code is still Fusion-C's (an assembler object, convention neutral).
SET INC1=%INCLUDEDIR%\crt0_msxdos.rel
SET ADDR_CODE=0x106
SET ADDR_DATA=0x0

echo -------- Compilation of : fusion46 and msxpi-bios
python tools\build_fusion46.py C-common\lib
IF ERRORLEVEL 1 EXIT /B 1
sdcc -mz80 -c C-common\lib\msxpi-bios.c
sdar -rc C-common\lib\msxpi-bios.lib msxpi-bios.rel
del msxpi-bios.lst
del msxpi-bios.sym
del msxpi-bios.rel
del msxpi-bios.asm

echo -------- Compilation of : %1

SET LINKLOG=%sourcename%.linklog
SDCC --code-loc %ADDR_CODE% --data-loc %ADDR_DATA% --disable-warning 196 -mz80 --no-std-crt0 --opt-code-size fusion46.lib msxpi-bios.lib -L %MSXPILIB% %INC1% %proga%.c > %LINKLOG% 2>&1
type %LINKLOG%
REM Permanent link guards: a module built with another calling convention, or a missing symbol.
findstr /C:"Conflicting sdcc options" %LINKLOG% >nul
IF NOT ERRORLEVEL 1 (
    echo ERROR: %sourcename% mixes calling conventions ^(linker: Conflicting sdcc options^).
    del %LINKLOG%
    del %sourcename%.ihx 2>nul
    EXIT /B 1
)
findstr /C:"Undefined Global" %LINKLOG% >nul
IF NOT ERRORLEVEL 1 (
    echo ERROR: %sourcename% has undefined symbols ^(linker: Undefined Global^).
    del %LINKLOG%
    del %sourcename%.ihx 2>nul
    EXIT /B 1
)
del %LINKLOG%
IF NOT EXIST %sourcename%.ihx GOTO _end_
echo ... Compilation OK

%HEX2BIN% -e com %sourcename%.ihx
echo off
IF DEFINED MAKE_OUTDIR GOTO _outdir_
copy %sourcename%.com %TARGETDIR%\%sourcename%.com /y
copy %sourcename%.com %FLOPPYA%\%sourcename%.com /y
copy target\*.BAS %FLOPPYA%%\ /y
IF DEFINED KEEPMAP copy %sourcename%.map %TARGETDIR%\%sourcename%.map /y
GOTO _cleanup_
:_outdir_
copy %sourcename%.com %MAKE_OUTDIR%\%sourcename%.com /y
IF DEFINED KEEPMAP copy %sourcename%.map %MAKE_OUTDIR%\%sourcename%.map /y
:_cleanup_
del %TARGETDIR%\..\%sourcename%.com
del %TARGETDIR%\..\%sourcename%.asm
del %TARGETDIR%\..\%sourcename%.ihx
del %TARGETDIR%\..\%sourcename%.lk
del %TARGETDIR%\..\%sourcename%.lst
del %TARGETDIR%\..\%sourcename%.map
del %TARGETDIR%\..\%sourcename%.noi
del %TARGETDIR%\..\%sourcename%.sym
del %TARGETDIR%\..\%sourcename%.rel
echo Done.
:_end_
