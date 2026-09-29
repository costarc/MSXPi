@echo off
rem MSXPi Interface - self-contained openMSX + MSXPi installer for Windows
rem ---------------------------------------------------------------------------
rem MIT License - Copyright (c) 2015-2026 Ronivon Costa
rem ---------------------------------------------------------------------------
rem Installs, with no administrator rights:
rem   C:\home\pi\msxpi           msxpi-server and modules, ini files, disks
rem   C:\home\pi\msxpi\openMSX   openMSX (MSXPi build) with MSXPi.xml and
rem                              msxpibios.rom in share\extensions / systemroms
rem   C:\home\pi\msxpi\start-openmsx.bat
rem Everything is downloaded from the costarc/MSXPi master branch; openMSX is
rem the MSXPi-enabled Windows build from the costarc/openMSX releases.
rem
rem For the MSX TCP/IP network (TAP driver + NAT) use msxpi-windows-setup.ps1.
rem Re-running is safe: files are refreshed, msxpi.ini and disks are kept.
rem
rem Usage: double-click, or  msxpi-openmsx-install.bat [branch]
powershell -NoProfile -ExecutionPolicy Bypass -Command "$b='%~1'; iex ((Get-Content -Raw -LiteralPath '%~f0') -split ('#'+'PS'+'#'))[1]"
echo.
pause
exit /b
#PS#
$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Branch  = if ($b) { $b } else { "master" }
$Home_   = "C:\home\pi\msxpi"
$OpenMsx = "$Home_\openMSX"
$Machine = "Panasonic_FS-A1WSX"
$Raw     = "https://raw.githubusercontent.com/costarc/MSXPi/$Branch/software"
$Work    = Join-Path $env:TEMP "msxpi-openmsx-install"

function Ok([string]$m)   { Write-Host "    ok   $m" -ForegroundColor Green }
function Warn([string]$m) { Write-Host "    warn $m" -ForegroundColor Yellow }
function Step([string]$m) { Write-Host ""; Write-Host "==> $m" -ForegroundColor Cyan }
function Fail([string]$m) { Write-Host "install failed: $m" -ForegroundColor Red; exit 1 }

function Get-File([string]$url, [string]$dest, [switch]$Optional) {
    try {
        Invoke-WebRequest -Uri $url -OutFile "$dest.new" -UseBasicParsing
        Move-Item -Force "$dest.new" $dest
        Ok (Split-Path -Leaf $dest)
    } catch {
        Remove-Item -Force "$dest.new" -ErrorAction SilentlyContinue
        if ($Optional) { Warn "$(Split-Path -Leaf $dest) not downloaded" } else { Fail "download failed: $url" }
    }
}

function Find-Python {
    # Skip the Microsoft Store python.exe stub: it only opens the Store.
    foreach ($c in @("py -3", "python")) {
        $exe, $arg = $c -split ' ', 2
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        try {
            $v = if ($arg) { & $exe $arg --version 2>&1 } else { & $exe --version 2>&1 }
            if ("$v" -match '^Python 3\.(\d+)' -and [int]$Matches[1] -ge 9) {
                $p = if ($arg) { & $exe $arg -c "import sys;print(sys.executable)" } else { & $exe -c "import sys;print(sys.executable)" }
                return "$p".Trim()
            }
        } catch { }
    }
    return $null
}

Write-Host "MSXPi + openMSX installer ($Branch) -> $Home_"
New-Item -ItemType Directory -Force $Home_, "$Home_\disks", "$Home_\native", $Work | Out-Null

# --- Python ---------------------------------------------------------------------
Step "Python 3"
$python = Find-Python
if (-not $python -and (Get-Command winget -ErrorAction SilentlyContinue)) {
    & winget install --id Python.Python.3.12 -e --silent --scope user --accept-package-agreements --accept-source-agreements
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    $python = Find-Python
    if (-not $python -and (Test-Path "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe")) {
        $python = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
    }
}
if (-not $python) { Fail "Python 3.9+ not found - install it from python.org and run this again" }
Ok $python

# Third-party modules the server imports. Only requests is needed to start;
# the others serve single commands, so a failure there is a warning.
#   pip name  = import name  (command)
$PyRequired = [ordered]@{ "requests" = "requests" }
$PyOptional = [ordered]@{ "certifi" = "certifi"          # pchess lobby TLS
                          "chess==1.11.2" = "chess"      # pchess
                          "Pillow" = "PIL"               # renderpage
                          "playwright" = "playwright" }  # renderpage

function Invoke-Py([string[]]$argv) {
    # pip and Python write notices to stderr; under "Stop" PowerShell 5.1
    # would turn them into errors. Return only the exit code.
    $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
    try { & $python @argv 2>&1 | Out-Null; return $LASTEXITCODE } finally { $ErrorActionPreference = $old }
}

Step "Python packages"
# A fresh or embedded Python may have no pip at all.
if ((Invoke-Py @("-m", "pip", "--version")) -ne 0) {
    if ((Invoke-Py @("-m", "ensurepip", "--upgrade")) -ne 0) { Fail "pip is missing from $python and ensurepip could not install it" }
    Ok "pip installed"
}
Invoke-Py @("-m", "pip", "install", "--upgrade", "--quiet", "pip") | Out-Null
foreach ($set in @(@{ Pkgs = $PyRequired; Required = $true }, @{ Pkgs = $PyOptional; Required = $false })) {
    foreach ($pkg in $set.Pkgs.Keys) {
        $mod = $set.Pkgs[$pkg]
        if ((Invoke-Py @("-W", "ignore", "-c", "import $mod")) -ne 0) {
            Invoke-Py @("-m", "pip", "install", "--upgrade", "--quiet", $pkg) | Out-Null
        }
        if ((Invoke-Py @("-W", "ignore", "-c", "import $mod")) -eq 0) { Ok $pkg }
        elseif ($set.Required) { Fail "Python package '$pkg' could not be installed - run: `"$python`" -m pip install $pkg" }
        else { Warn "$pkg not installed - the command that uses it will not work" }
    }
}
# playwright drives a headless Chromium for renderpage; it is a separate download.
if ((Invoke-Py @("-W", "ignore", "-c", "import playwright")) -eq 0) {
    if ((Invoke-Py @("-m", "playwright", "install", "chromium")) -eq 0) { Ok "Chromium for playwright" }
    else { Warn "Chromium for playwright not installed - renderpage will not work" }
}

# --- MSXPi server ---------------------------------------------------------------
Step "MSXPi server"
$srv = "$Raw/Server/Python/src"
# Every module msxpi-server.py imports; keep in sync with msxpi-windows-setup.ps1.
foreach ($f in @("msxpi-server.py", "msxpi_const.py", "msxpi_settings.py", "msxpi_transport.py", "msxpi_blocks.py",
                 "msxpi_cmd_disk.py", "msxpi_cmd_files.py", "msxpi_cmd_media.py", "msxpi_cmd_rom.py",
                 "msxpi_cmd_stock.py", "msxpi_cmd_system.py", "msxpi_cmd_web.py",
                 "msxpi_eth.py", "msxpi_ethglue.py", "msxpi_gpio_native.py", "msxpi_player.py",
                 "msxpi_renderpage.py", "mapper_detect.py", "msxpi_pchess.py", "msxpi_pchess_irc.py")) {
    Get-File "$srv/$f" "$Home_\$f"
}
foreach ($f in @("msxpi-JumperLeft.ini", "msxpi-JumperRight.ini", "msxpi-JumperRight_PCBV1.1Rev.0.ini")) {
    Get-File "$srv/$f" "$Home_\$f" -Optional
}
# msxpi.ini holds the user's keys and settings: never overwrite it.
if (-not (Test-Path "$Home_\msxpi.ini")) { Copy-Item "$Home_\msxpi-JumperLeft.ini" "$Home_\msxpi.ini"; Ok "msxpi.ini created" }
else { Ok "msxpi.ini kept" }
foreach ($f in @("msxpiboot.dsk", "tools.dsk", "blank.dsk")) {
    if (Test-Path "$Home_\disks\$f") { Ok "$f kept" } else { Get-File "$Raw/target/disks/$f" "$Home_\disks\$f" -Optional }
}

# --- openMSX --------------------------------------------------------------------
Step "openMSX"
# The build must match the MSXPi ROM and server (CPLD v1.6 emulation): the
# installed build is recorded, and a different one is replaced.
$OmBuild = "openmsx-21.0-547-g352e335f5-mingw-w64-x86_64-bin.zip"
$OmUrl   = "https://github.com/costarc/openMSX/releases/download/openMSX/$OmBuild"
$OmStamp = "$OpenMsx\msxpi-openmsx-build.txt"
if ((Test-Path "$OpenMsx\openmsx.exe") -and (Test-Path $OmStamp) -and ((Get-Content -Raw $OmStamp).Trim() -eq $OmBuild)) {
    Ok "$OmBuild already in $OpenMsx"
} else {
    Write-Host "    downloading $OmBuild"
    $zip = Join-Path $Work "openmsx.zip"
    Get-File $OmUrl $zip
    # Some builds are zipped twice (name.zip.zip): unpack until openmsx.exe appears.
    $x = Join-Path $Work "x0"
    Remove-Item -Recurse -Force $x -ErrorAction SilentlyContinue
    Expand-Archive $zip $x -Force
    for ($i = 1; $i -le 3 -and -not (Get-ChildItem $x -Recurse -Filter openmsx.exe); $i++) {
        $inner = Get-ChildItem $x -Recurse -Filter *.zip | Select-Object -First 1
        if (-not $inner) { break }
        Remove-Item -Recurse -Force "$Work\x$i" -ErrorAction SilentlyContinue
        Expand-Archive $inner.FullName "$Work\x$i" -Force
        $x = "$Work\x$i"
    }
    $exe = Get-ChildItem $x -Recurse -Filter openmsx.exe | Select-Object -First 1
    if (-not $exe) { Fail "openmsx.exe not found in $OmBuild" }
    New-Item -ItemType Directory -Force $OpenMsx | Out-Null
    Copy-Item "$($exe.DirectoryName)\*" $OpenMsx -Recurse -Force
    Set-Content -Encoding ASCII $OmStamp $OmBuild
    Ok "$OmBuild installed to $OpenMsx"
}
# Always refresh the extension and BIOS together, so the ROM sha1 matches the XML.
New-Item -ItemType Directory -Force "$OpenMsx\share\extensions", "$OpenMsx\share\systemroms" | Out-Null
Get-File "$Raw/openMSX/share/extensions/MSXPi.xml" "$OpenMsx\share\extensions\MSXPi.xml"
Get-File "$Raw/target/msxpibios.rom" "$OpenMsx\share\systemroms\msxpibios.rom"

# --- Startup batch --------------------------------------------------------------
Step "Startup batch"
@"
@echo off
rem Start msxpi-server (if not running) and openMSX with the MSXPi extension.
cd /d "$Home_"
powershell -NoProfile -Command "if (Get-CimInstance Win32_Process -Filter \"Name like 'python%%'\" | Where-Object { `$_.CommandLine -like '*msxpi-server.py*' }) { exit 1 }"
if not errorlevel 1 (
    start "msxpi-server" /D "$Home_" "$python" "$Home_\msxpi-server.py"
    timeout /t 2 /nobreak >nul
)
start "openMSX" /D "$OpenMsx" "$OpenMsx\openmsx.exe" -machine $Machine -ext MSXPi -ext ram4mb
"@ | Set-Content -Encoding ASCII "$Home_\start-openmsx.bat"
Ok "$Home_\start-openmsx.bat"

Write-Host ""
Write-Host "Done. Start MSXPi with $Home_\start-openmsx.bat" -ForegroundColor Green
