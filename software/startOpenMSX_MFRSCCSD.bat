@echo off
Set MyProcess=openmsx.exe
tasklist | find /i "%MyProcess%">nul  && (echo %MyProcess% Already running) || start ..\..\..\MSX\MSXPi\openmsx-21.0-534-MSXPi_v1.6\openmsx.exe -script emul_start_config_MFRSCCSD.txt
:_end_