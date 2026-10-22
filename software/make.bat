@echo off

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
echo msxpi-lib.c
sdcc -mz80 -c C-common\lib\%MSXPIBIOSLIB%.c
sdar -rc C-common\lib\%MSXPIBIOSLIB%.lib %MSXPIBIOSLIB%.rel
del %MSXPIBIOSLIB%.lst
del %MSXPIBIOSLIB%.sym
del %MSXPIBIOSLIB%.rel
del %MSXPIBIOSLIB%.asm

echo -------- Compilation of : %1

REM PChess is near the MSX-DOS memory limit (a Canon V-25 with the TCP/IP driver loaded
REM has a TPA top of only 0xC806): the larger register-allocation search makes it
REM about 2.4 KB smaller than the default, at the price of a build of about 3 minutes
REM (30000 would take 1 minute but leave only 804 bytes; Client\tests\pchess_memory_test.py
REM checks the result).
SET OPTX=
IF /I "%1"=="pchess" SET OPTX=--max-allocs-per-node 100000
SDCC --code-loc %ADDR_CODE% --data-loc %ADDR_DATA% --disable-warning 196 -mz80 --no-std-crt0 --opt-code-size %OPTX% fusion.lib %MSXPIBIOSLIB%.lib -L %LIBDIR% -L %MSXPILIB% %INC1% %proga%.c
SET cpath=%~dp0
IF NOT EXIST %sourcename%.ihx GOTO _end_
echo ... Compilation OK

%HEX2BIN% -e com %sourcename%.ihx
echo off
copy %sourcename%.com %TARGETDIR%\%sourcename%.com /y
copy %sourcename%.com %FLOPPYA%\%sourcename%.com /y
copy target\*.BAS %FLOPPYA%%\ /y
IF DEFINED KEEPMAP copy %sourcename%.map %TARGETDIR%\%sourcename%.map /y
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