@echo off
Set MyProcess=openmsx.exe
tasklist | find /i "%MyProcess%">nul  && (echo %MyProcess% Already running) || start ..\..\..\MSX\MSXPi\openMSX\openmsx.exe -script emul_start_config.txt
:_end_