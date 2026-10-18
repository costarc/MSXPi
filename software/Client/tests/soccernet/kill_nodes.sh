#!/bin/sh
# Stop leftover test emulators of mine (only those running one of my node
# scripts): an old node keeps writing into the same result files.
powershell -NoProfile -Command "Get-CimInstance Win32_Process | Where-Object { \$_.Name -eq 'openmsx.exe' -and \$_.CommandLine -match 'udp_node|ping_node|node\.tcl' } | ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }" > /dev/null 2>&1
sleep 1
