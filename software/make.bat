@echo off

REM Requires SDCC 4.6.0 (the calling-convention port is built and tested on it).
sdcc --version | findstr /C:"4.6.0" >nul
IF ERRORLEVEL 1 (
    echo ERROR: SDCC 4.6.0 is required ^(sdcc --version must report 4.6.0^).
    EXIT /B 1
)

REM Programs already ported to SDCC 4.6's own calling convention (sdcccall 1): SDCC's own
REM stdlib, no --sdcccall 0, the repo's fusion library. Space-separated, lower case.
REM Every other program is still built the old way (--sdcccall 0): SDCC 4.6's runtime uses
REM the other convention, so the link warns "Conflicting sdcc options" and the build is
REM refused (SDCC_ALLOW_ABI_MIX=1 lets it through, only for software	oolsbi_bytecmp.py).
SET ABI1_PROGRAMS=templatc
SET ABI1=0
FOR %%P IN (%ABI1_PROGRAMS%) DO IF /I "%%P"=="%1" SET ABI1=1

REM MAKE_OUTDIR=<dir>: put the .com (and the .map with KEEPMAP) there only, not in targetREM and the shared FloppyA.

python asm-common\transport\generate.py --check
IF ERRORLEVEL 1 EXIT /B 1

SET BASEDIR=.
SET FLOPPYA=..\..\..\MSX\MSXPi\FloppyA
SET TARGETDIR=target
SET HEX2BINDIR="..\..\..\MSX\MSX-C\WorkingFolder\Tools\Hex2Bin\Hex2bin Windows"
SET HEX2BIN=%HEX2BINDIR%\hex2bin.exe 
SET ASM=sdasz80 
SET CC=sdcc 
SET DEST=dsk\
SET INCLUDEDIR=..\..\..\MSX\MSX-C\WorkingFolder\fusion-c\include
SET LIBDIR=..\..\..\MSX\MSX-C\WorkingFolder\fusion-c\lib
SET MSXPILIB=C-common\lib
SET proga=Client\src\%1
SET sourcename=%1
SET INC1=%INCLUDEDIR%\crt0_msxdos.rel
SET MSXPIBIOSLIB=msxpi-bios
SET ABIFLAGS=--sdcccall 0
SET FUSIONLIB=fusion.lib
IF "%ABI1%"=="1" (
    SET ABIFLAGS=-DMSXPI_FUSION46
    SET FUSIONLIB=fusion46.lib
    SET MSXPIBIOSLIB=msxpi-bios46
)
REM SET INC2=%INCLUDEDIR
REM SET INC3=%INCLUDEDIR
REM SET INC4=%INCLUDEDIR%
REM SET INC5=%INCLUDEDIR%
REM SET INC6=%INCLUDEDIR%
REM SET INC7=%INCLUDEDIR%
REM SET INC8=%INCLUDEDIR%
REM SET INC9=%INCLUDEDIR%
REM SET INCA=%INCLUDEDIR%
REM SET INCB=%INCLUDEDIR%
REM SET INCC=%INCLUDEDIR%
REM SET INCD=%INCLUDEDIR%
REM SET INCE=%INCLUDEDIR%
REM SET INCF=%INCLUDEDIR%
SET ADDR_CODE=0x106
SET ADDR_DATA=0x0

echo -------- Compilation of : %MSXPIBIOSLIB%
IF "%ABI1%"=="1" (
    python tools\build_fusion46.py C-common\lib
    IF ERRORLEVEL 1 EXIT /B 1
)
echo msxpi-lib.c
sdcc -mz80 %ABIFLAGS% -c C-common\lib\msxpi-bios.c
sdar -rc C-common\lib\%MSXPIBIOSLIB%.lib msxpi-bios.rel
del msxpi-bios.lst
del msxpi-bios.sym
del msxpi-bios.rel
del msxpi-bios.asm

echo -------- Compilation of : %1

REM PChess is near the MSX-DOS memory limit (a Canon V-25 with the TCP/IP driver loaded
REM has a TPA top of only 0xC806): the larger register-allocation search makes it
REM about 2.4 KB smaller than the default, at the price of a build of about 3 minutes
REM (30000 would take 1 minute but leave only 804 bytes; Client\tests\pchess_memory_test.py
REM checks the result).
SET OPTX=
IF /I "%1"=="pchess" SET OPTX=--max-allocs-per-node 100000
SET LINKLOG=%sourcename%.linklog
SDCC --code-loc %ADDR_CODE% --data-loc %ADDR_DATA% --disable-warning 196 -mz80 %ABIFLAGS% --no-std-crt0 --opt-code-size %OPTX% %FUSIONLIB% %MSXPIBIOSLIB%.lib -L %LIBDIR% -L %MSXPILIB% %INC1% %proga%.c > %LINKLOG% 2>&1
type %LINKLOG%
SET cpath=%~dp0
findstr /C:"Conflicting sdcc options" %LINKLOG% >nul
IF NOT ERRORLEVEL 1 IF NOT DEFINED SDCC_ALLOW_ABI_MIX (
    echo ERROR: %sourcename% mixes calling conventions ^(linker: Conflicting sdcc options^).
    echo        Port it to sdcccall 1 and add it to ABI1_PROGRAMS, or set SDCC_ALLOW_ABI_MIX=1.
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
:Emulator
Set MyProcess=openmsx.exe
REM tasklist | find /i "%MyProcess%">nul  && (echo %MyProcess% Already running) || start ..\..\..\MSX\MSXPi\openMSX\openmsx.exe -script emul_start_config_MFRSCCSD.txt
:_end_