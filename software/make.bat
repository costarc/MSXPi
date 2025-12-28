@echo off

SET BASEDIR=.
SET FLOPPYA=..\..\..\MSX\MSXPi\diska22
SET TARGETDIR=target
SET HEX2BINDIR="..\..\..\MSX-C\WorkingFolder\Tools\Hex2Bin\Hex2bin Windows"
SET HEX2BIN=%HEX2BINDIR%\hex2bin.exe 
SET ASM=sdasz80 
SET CC=sdcc 
SET DEST=dsk\
SET INCLUDEDIR=..\..\..\MSX-C\WorkingFolder\fusion-c\include
SET LIBDIR=..\..\..\MSX-C\WorkingFolder\fusion-c\lib
SET MSXPILIB=C-common\lib
SET proga=Client\src\%1
SET sourcename=%1
SET INC1=%INCLUDEDIR%\crt0_msxdos.rel
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

echo -------- Compilation of : msxpi-lib
echo msxpi-lib.c
sdcc -mz80 -c C-common\lib\msxpi-bios.c
sdar -rc C-common\lib\msxpi-bios.lib msxpi-bios.rel
del msxpi-bios.lst
del msxpi-bios.sym
del msxpi-bios.rel
del msxpi-bios.asm

echo -------- Compilation of : %1

SDCC --code-loc %ADDR_CODE% --data-loc %ADDR_DATA% --disable-warning 196 -mz80 --no-std-crt0 --opt-code-size fusion.lib msxpi-bios.lib -L %LIBDIR% -L %MSXPILIB% %INC1% %proga%.c
SET cpath=%~dp0
IF NOT EXIST %sourcename%.ihx GOTO _end_
echo ... Compilation OK

%HEX2BIN% -e com %sourcename%.ihx

copy %sourcename%.com %TARGETDIR%\%sourcename%.com /y
copy %sourcename%.com %FLOPPYA%\%sourcename%.com /y
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
tasklist | find /i "%MyProcess%">nul  && (echo %MyProcess% Already running) || start ..\..\..\MSX\MSXPi\openMSX\openmsx.exe -script emul_start_config.txt
:_end_