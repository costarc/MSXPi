<#
    MSXPi Interface
    Version 1.6.1
    ------------------------------------------------------------------------------
    MIT License

    Copyright (c) 2015-2026 Ronivon Costa

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    ------------------------------------------------------------------------------

    Install MSXPi (emulated, under openMSX) on Windows. The Windows counterpart
    of msxpi-setup.sh. Double-click msxpi-openmsx-install.bat, or:

        powershell -ExecutionPolicy Bypass -File msxpi-windows-setup.ps1 [-Network]

    Everything lands in C:\home\pi\msxpi (the server hardcodes /home/pi/msxpi,
    which Windows resolves on the current drive) and needs no administrator
    rights, except -Network:

      1. Python 3 [winget] and the packages the server imports: requests
         (required); certifi, chess and Stockfish [winget] for pchess; Pillow,
         playwright and its Chromium for renderpage. 7-Zip [winget] for
         zip/lzh/pma, mpv for media playback.
      2. The server, its modules, ini files and disk images from the costarc/MSXPi
         branch (default master). msxpi.ini and existing disks are kept.
      3. openMSX in C:\home\pi\msxpi\openMSX: the MSXPi build (CPLD v1.6
         emulation) from the costarc/openMSX releases, with MSXPi.xml and
         msxpibios.rom from the same branch as the server.
      4. -Network (asks for administrator rights): the OpenVPN TAP driver, and a
         network check the launcher runs to set up the MSX network (NAT).
      5. start-openmsx.bat launcher and a desktop shortcut.

    Re-running is safe: every step checks what is already there. openMSX is
    replaced when it is not the build this script pins.
#>

[CmdletBinding()]
param(
    [string]$MsxPiHome   = "C:\home\pi\msxpi",
    [string]$Branch      = "master",
    [string]$Machine     = "Panasonic_FS-A1WSX",
    # Local path or URL of an openMSX Windows zip, instead of the pinned build.
    [string]$OpenMsxZip  = "",
    [string]$TapUrl      = "https://build.openvpn.net/downloads/releases/tap-windows-9.24.2-I601-Win10.exe",
    [switch]$Network,
    [switch]$SkipPython,
    [switch]$SkipMpv,
    [switch]$SkipOpenMsx,
    [switch]$NoPause
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # Invoke-WebRequest is 10x slower with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# The openMSX build the MSXPi ROM and server are made for. When it changes,
# existing installs are replaced on the next run.
$OpenMsxRelease = "MSXPi_v1.6.1"
$OpenMsxBuild   = "openmsx-21.0-577-g74d1910d1-mingw-w64-x86_64-bin.zip"
$OpenMsxUrl     = "https://github.com/costarc/openMSX/releases/download/$OpenMsxRelease/$OpenMsxBuild"

$Raw        = "https://raw.githubusercontent.com/costarc/MSXPi/$Branch/software"
$OpenMsxDir = "$MsxPiHome\openMSX"
$openmsxExe = "$OpenMsxDir\openmsx.exe"
$Work       = Join-Path $env:TEMP "msxpi-setup"
New-Item -ItemType Directory -Force $Work | Out-Null

function Step([string]$msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok([string]$msg)   { Write-Host "    ok   $msg" -ForegroundColor Green }
function Warn([string]$msg) { Write-Host "    warn $msg" -ForegroundColor Yellow }
function Exit-Setup([int]$code) {
    # Started from Explorer the window closes on exit; keep it up to be read.
    if (-not $NoPause) { Write-Host ""; Read-Host "Press Enter to close" | Out-Null }
    exit $code
}
function Fail([string]$msg) { Write-Host "msxpi-windows-setup: $msg" -ForegroundColor Red; Exit-Setup 1 }

function Get-File([string]$url, [string]$dest, [switch]$Optional) {
    try {
        Invoke-WebRequest -Uri $url -OutFile "$dest.new" -UseBasicParsing
        Move-Item -Force "$dest.new" $dest
        Ok (Split-Path -Leaf $dest)
        return $true
    } catch {
        Remove-Item -Force "$dest.new" -ErrorAction SilentlyContinue
        if ($Optional) { Warn "$(Split-Path -Leaf $dest) not downloaded ($url)"; return $false }
        Fail "download failed: $url`n    $($_.Exception.Message)"
    }
}

# Run Python and return its exit code. Python writes warnings to stderr even
# when it succeeds, and Windows PowerShell 5.1 turns any stderr line into a
# terminating error under $ErrorActionPreference = "Stop": so the preference
# is relaxed here. With -Text, return the last output line as well.
function Invoke-Py([string[]]$argv, [switch]$Text) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & $python @argv 2>&1
        if ($Text) { return [pscustomobject]@{ Code = $LASTEXITCODE; Text = "$($out | Select-Object -Last 1)" } }
        return $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $old
    }
}
function Test-PyImport([string]$module) { Invoke-Py @("-W", "ignore", "-c", "import $module") -Text }

function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Assert-Admin {
    # Relaunch elevated (one UAC prompt) instead of failing. The bound
    # parameters travel along to the elevated copy.
    $p = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    if ($p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { return }
    $argv = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSCommandPath`"")
    foreach ($k in $script:PSBoundParameters.Keys) {
        $v = $script:PSBoundParameters[$k]
        if ($v -is [switch]) { if ($v) { $argv += "-$k" } } else { $argv += "-$k"; $argv += "`"$v`"" }
    }
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList $argv | Out-Null
    } catch {
        Fail "-Network needs administrator rights (TAP driver install) - the UAC prompt was declined"
    }
    exit 0
}

function Find-Python {
    # The Microsoft Store "python.exe" stub is on PATH even with no Python
    # installed; it opens the Store instead of running. Ask for a version to
    # tell a real interpreter from the stub.
    foreach ($c in @("py -3", "python")) {
        $exe, $arg = $c -split ' ', 2
        if (-not (Get-Command $exe -ErrorAction SilentlyContinue)) { continue }
        try {
            $v = if ($arg) { & $exe $arg --version 2>&1 } else { & $exe --version 2>&1 }
            if ("$v" -match '^Python 3\.(\d+)' -and [int]$Matches[1] -ge 9) {
                $path = if ($arg) { & $exe $arg -c "import sys;print(sys.executable)" } else { & $exe -c "import sys;print(sys.executable)" }
                return "$path".Trim()
            }
        } catch { }
    }
    return $null
}

function Install-Winget([string]$id, [string]$what) {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Warn "winget not found - install $what manually (or install 'App Installer' from the Store)"
        return
    }
    # Per-user first, so no administrator rights are needed; some packages
    # only come as a machine-wide install, and ask for elevation themselves.
    & winget install --id $id -e --silent --scope user --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        & winget install --id $id -e --silent --accept-package-agreements --accept-source-agreements
    }
    # winget returns non-zero for "already installed"; the caller re-checks.
    Update-Path
}

function Add-UserPath([string]$dir) {
    $up = [Environment]::GetEnvironmentVariable("Path", "User")
    if (($up -split ';') -notcontains $dir) {
        [Environment]::SetEnvironmentVariable("Path", $(if ($up) { "$up;$dir" } else { $dir }), "User")
    }
    Update-Path
}

function Install-Mpv {
    $mpvExe = "C:\Apps\mpv\mpv.exe"
    Step "mpv"
    if (Test-Path $mpvExe) { Ok "already installed"; return }
    try {
        $api = Invoke-RestMethod "https://api.github.com/repos/mpv-distributions/mpv-windows-setup/releases/latest"
        $asset = $api.assets | Where-Object { $_.name -eq "mpv-setup-x86_64-$($api.tag_name).exe" } | Select-Object -First 1
        if (-not $asset) { throw "no x86_64 installer in $($api.tag_name)" }
        $installer = Join-Path $Work $asset.name
        Get-File $asset.browser_download_url $installer | Out-Null
        & $installer /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=C:\Apps\mpv
    } catch {
        Warn "mpv not installed ($($_.Exception.Message)) - media playback will not work"
        return
    }
    if (Test-Path $mpvExe) { Ok "installed in C:\Apps\mpv" } else { Warn "mpv installation did not produce $mpvExe" }
}

if ($Network) { Assert-Admin }
Write-Host "MSXPi Windows setup ($Branch)"
Write-Host "  home    : $MsxPiHome"
Write-Host "  openMSX : $OpenMsxDir"
Write-Host "  network : $(if ($Network) { 'yes' } else { 'no (run with -Network for MSX TCP/IP)' })"

# --- 1. Python, packages and tools ---------------------------------------------
$python = $null
if (-not $SkipPython) {
    Step "Python 3"
    $python = Find-Python
    if (-not $python) {
        Install-Winget "Python.Python.3.12" "Python 3"
        $python = Find-Python
        if (-not $python) {
            foreach ($p in @("$env:LOCALAPPDATA\Programs\Python\Python312\python.exe", "$env:ProgramFiles\Python312\python.exe")) {
                if (Test-Path $p) { $python = $p; break }
            }
        }
        if (-not $python) { Fail "Python 3.9+ not found - install it from python.org and run this again" }
    }
    Ok "$python ($(& $python --version 2>&1))"

    Step "Python packages"
    # Third-party modules the server imports. Only requests is needed to start;
    # the others serve single commands, so a failure there is a warning.
    #   pip name  = import name  (command)
    $pyRequired = [ordered]@{ "requests" = "requests" }
    $pyOptional = [ordered]@{ "certifi" = "certifi"          # pchess lobby TLS
                              "chess==1.11.2" = "chess"      # pchess
                              "Pillow" = "PIL"               # renderpage
                              "playwright" = "playwright" }  # renderpage

    # A fresh or embedded Python may have no pip at all.
    if ((Invoke-Py @("-m", "pip", "--version")) -ne 0) {
        if ((Invoke-Py @("-m", "ensurepip", "--upgrade")) -ne 0) { Fail "pip is missing from $python and ensurepip could not install it" }
        Ok "pip installed"
    }
    Invoke-Py @("-m", "pip", "install", "--upgrade", "--quiet", "pip") | Out-Null
    foreach ($set in @(@{ Pkgs = $pyRequired; Required = $true }, @{ Pkgs = $pyOptional; Required = $false })) {
        foreach ($pkg in $set.Pkgs.Keys) {
            $mod = $set.Pkgs[$pkg]
            if ((Test-PyImport $mod).Code -ne 0) {
                Invoke-Py @("-m", "pip", "install", "--upgrade", "--quiet", $pkg) | Out-Null
            }
            $chk = Test-PyImport $mod
            if ($chk.Code -eq 0) { Ok $pkg }
            elseif ($set.Required) { Fail "Python package '$pkg' does not import: $($chk.Text)`n    run: `"$python`" -m pip install $pkg (an error about long paths is fixed by enabling Windows long path support, or by installing Python from python.org into a short folder)" }
            else { Warn "$pkg does not import - the command that uses it will not work: $($chk.Text)" }
        }
    }
    # playwright drives a headless Chromium for renderpage; it is a separate download.
    if ((Test-PyImport "playwright").Code -eq 0) {
        if ((Invoke-Py @("-m", "playwright", "install", "chromium")) -eq 0) { Ok "Chromium for playwright" }
        else { Warn "Chromium for playwright not installed - renderpage will not work" }
    }

    # Stockfish is the pchess AI opponent; without it a weaker built-in AI plays.
    # The server finds winget's install by itself (PATH alias or WinGet\Packages).
    Step "Stockfish (pchess AI)"
    if (Get-Command stockfish -ErrorAction SilentlyContinue) {
        Ok "already on PATH"
    } else {
        Install-Winget "Stockfish.Stockfish" "Stockfish"
        $sf = Get-ChildItem "$env:ProgramFiles\WinGet\Packages", "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" `
                -Recurse -Filter "stockfish*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ((Get-Command stockfish -ErrorAction SilentlyContinue) -or $sf) { Ok "installed" }
        else { Warn "Stockfish not installed - pchess uses its weaker built-in AI (or set PCHESSENGINE in msxpi.ini)" }
    }

    Step "7-Zip"
    # The server runs plain "7z.exe", so any copy on PATH will do.
    $onPath = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($onPath) {
        Ok "$($onPath.Source) (already on PATH)"
    } else {
        $dirs = @("$env:ProgramFiles\7-Zip", "${env:ProgramFiles(x86)}\7-Zip", "$env:LOCALAPPDATA\Programs\7-Zip")
        $sevenZip = $dirs | Where-Object { Test-Path "$_\7z.exe" } | Select-Object -First 1
        if (-not $sevenZip) {
            Install-Winget "7zip.7zip" "7-Zip"
            $sevenZip = $dirs | Where-Object { Test-Path "$_\7z.exe" } | Select-Object -First 1
        }
        if ($sevenZip) { Add-UserPath $sevenZip; Ok "$sevenZip\7z.exe (added to PATH)" }
        else { Warn "7-Zip not installed - zip/lzh/pma files will not open" }
    }
}
if (-not $SkipMpv) { Install-Mpv }

# --- 2. MSXPi home ------------------------------------------------------------
Step "MSXPi home $MsxPiHome"
foreach ($d in @($MsxPiHome, "$MsxPiHome\disks", "$MsxPiHome\native")) {
    New-Item -ItemType Directory -Force $d | Out-Null
}

$srv = "$Raw/Server/Python/src"
# Every module msxpi-server.py imports (directly or lazily). Keep in sync with Python/src.
foreach ($f in @("msxpi-server.py", "msxpi_const.py", "msxpi_settings.py", "msxpi_transport.py", "msxpi_blocks.py",
                 "msxpi_cmd_disk.py", "msxpi_cmd_files.py", "msxpi_cmd_media.py", "msxpi_cmd_rom.py",
                 "msxpi_cmd_stock.py", "msxpi_cmd_system.py", "msxpi_cmd_web.py",
                 "msxpi_eth.py", "msxpi_ethglue.py", "msxpi_gpio_native.py", "msxpi_player.py",
                 "msxpi_renderpage.py", "msxpi_nitros.py", "mapper_detect.py", "msxpi_pchess.py", "msxpi_pchess_irc.py")) {
    Get-File "$srv/$f" "$MsxPiHome\$f" | Out-Null
}
foreach ($f in @("msxpi-JumperLeft.ini", "msxpi-JumperRight.ini", "msxpi-JumperRight_PCBV1.1Rev.0.ini")) {
    Get-File "$srv/$f" "$MsxPiHome\$f" -Optional | Out-Null
}

# Never overwrite msxpi.ini: it holds the user's API keys and PSET values.
if (-not (Test-Path "$MsxPiHome\msxpi.ini")) {
    Copy-Item "$MsxPiHome\msxpi-JumperLeft.ini" "$MsxPiHome\msxpi.ini"
    Ok "msxpi.ini created"
} else {
    Ok "msxpi.ini kept"
}

foreach ($f in @("msxpiboot.dsk", "tools.dsk")) {
    if (-not (Test-Path "$MsxPiHome\disks\$f")) {
        Get-File "$Raw/target/disks/$f" "$MsxPiHome\disks\$f" -Optional | Out-Null
    } else {
        Ok "$f kept"
    }
}

# --- 3. openMSX -----------------------------------------------------------------
if (-not $SkipOpenMsx) {
    Step "openMSX"
    # The installed build is recorded; a different one is replaced, since the
    # ROM and server only work with an openMSX that has the CPLD emulation.
    $want  = if ($OpenMsxZip) { Split-Path -Leaf $OpenMsxZip } else { $OpenMsxBuild }
    $stamp = "$OpenMsxDir\msxpi-openmsx-build.txt"
    $have  = if (Test-Path $stamp) { (Get-Content -Raw $stamp).Trim() } else { "" }
    if ((Test-Path $openmsxExe) -and $have -eq $want) {
        Ok "$want already installed"
    } else {
        if (Get-Process openmsx -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $openmsxExe }) {
            Fail "openMSX is running from $OpenMsxDir - close it and run this again"
        }
        $src = if ($OpenMsxZip) { $OpenMsxZip } else { $OpenMsxUrl }
        $zip = Join-Path $Work "openmsx.zip"
        if ($src -match '^https?://') {
            Write-Host "    downloading $want"
            Get-File $src $zip | Out-Null
        } else {
            Copy-Item $src $zip -Force
        }

        # Some builds are zipped twice (name.zip.zip): unpack until openmsx.exe appears.
        $x = Join-Path $Work "openmsx-x"
        Remove-Item -Recurse -Force $x -ErrorAction SilentlyContinue
        Expand-Archive $zip $x -Force
        for ($i = 0; $i -lt 3 -and -not (Get-ChildItem $x -Recurse -Filter openmsx.exe); $i++) {
            $inner = Get-ChildItem $x -Recurse -Filter *.zip | Select-Object -First 1
            if (-not $inner) { break }
            $next = "$x-$i"
            Remove-Item -Recurse -Force $next -ErrorAction SilentlyContinue
            Expand-Archive $inner.FullName $next -Force
            $x = $next
        }
        $exe = Get-ChildItem $x -Recurse -Filter openmsx.exe | Select-Object -First 1
        if (-not $exe) { Fail "openmsx.exe not found inside $src" }

        New-Item -ItemType Directory -Force $OpenMsxDir | Out-Null
        # An openMSX unpacked by WSL or a Linux tool keeps the source tree's
        # symlinks (share\machines\msx1.xml and others) as WSL links, which
        # Windows cannot open or overwrite. Remove links before copying over them.
        Get-ChildItem $OpenMsxDir -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Copy-Item "$($exe.DirectoryName)\*" $OpenMsxDir -Recurse -Force
        Set-Content -Encoding ASCII $stamp $want
        Ok "$want installed"
    }

    # Extension and BIOS always from the same branch, so the ROM's sha1 is one the XML knows.
    New-Item -ItemType Directory -Force "$OpenMsxDir\share\extensions", "$OpenMsxDir\share\systemroms" | Out-Null
    Get-File "$Raw/openMSX/share/extensions/MSXPi.xml" "$OpenMsxDir\share\extensions\MSXPi.xml" | Out-Null
    Get-File "$Raw/target/msxpibios.rom" "$OpenMsxDir\share\systemroms\msxpibios.rom" | Out-Null
}

# --- 4. TAP driver and network check ---------------------------------------------
function Get-Tap {
    Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -like "TAP-Windows Adapter*" } |
        Select-Object -First 1
}

if ($Network) {
    Step "OpenVPN TAP driver"
    $created = $false
    $addtap = "$env:ProgramFiles\TAP-Windows\bin\addtap.bat"
    if (Get-Tap) {
        Ok "adapter already present"
    } elseif (Test-Path $addtap) {
        # Driver installed (by OpenVPN, say) but no adapter left: add one
        # rather than running the installer again.
        Write-Host "    driver present, adding an adapter"
        & cmd /c "`"$addtap`"" | Out-Null
        Start-Sleep -Seconds 3
        $created = $true
    } else {
        $inst = Join-Path $Work "tap-windows.exe"
        Get-File $TapUrl $inst | Out-Null
        Write-Host "    installing (Windows may ask to trust the OpenVPN publisher)"
        $p = Start-Process $inst -ArgumentList "/S" -Wait -PassThru
        if ($p.ExitCode -ne 0) { Fail "TAP installer exit code $($p.ExitCode)" }
        Start-Sleep -Seconds 3
        if (-not (Get-Tap) -and (Test-Path $addtap)) {
            & cmd /c "`"$addtap`"" | Out-Null
            Start-Sleep -Seconds 3
        }
        $created = $true
    }
    $tap = Get-Tap
    if (-not $tap) { Fail "no TAP-Windows adapter after install" }
    # Only name an adapter this script created; an existing one may belong to
    # an OpenVPN profile that refers to it by name.
    if ($created -and $tap.Name -ne "MSXPi") {
        try { Rename-NetAdapter -Name $tap.Name -NewName "MSXPi"; $tap = Get-Tap } catch { Warn "could not rename '$($tap.Name)' to MSXPi" }
    }
    Ok "$($tap.Name) [$($tap.InterfaceDescription)]"

    Get-File "$Raw/Server/Setup/msxpi-tcpip-setup.ps1" "$MsxPiHome\msxpi-tcpip-setup.ps1" | Out-Null
    # The MSX network (TAP address + NAT) is not configured here: the launcher
    # runs this check each time and asks for elevation only when it is missing.
    @'
# MSXPi network check, run by start-openmsx.bat before the server starts.
# Reading the NAT and the address needs no administrator rights; only
# (re)creating them does, so UAC appears only when something is missing.
$tap = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceDescription -like "TAP-Windows Adapter*" } | Select-Object -First 1
if (-not $tap) { exit 0 }
$nat = Get-NetNat -Name MSXPi -ErrorAction SilentlyContinue
$ip  = Get-NetIPAddress -InterfaceIndex $tap.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
       Where-Object { $_.IPAddress -eq "192.168.99.1" }
if ($nat -and $ip) { exit 0 }
Write-Host "MSX network not configured - requesting administrator rights to set it up"
try {
    Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$PSScriptRoot\msxpi-tcpip-setup.ps1`"")
} catch {
    Write-Host "Skipped: MSXPi runs, but the MSX has no TCP/IP."
}
'@ | Set-Content -Encoding UTF8 "$MsxPiHome\msxpi-netcheck.ps1"
    Ok "msxpi-netcheck.ps1"

    # Remove the boot-time task an earlier version of this script made.
    Unregister-ScheduledTask -TaskName "MSXPi TCPIP Setup" -Confirm:$false -ErrorAction SilentlyContinue
}

# --- 5. Launcher ------------------------------------------------------------------
Step "Launcher"
if (-not $python) { $python = Find-Python }
if (-not $python) { $python = "python" }
@"
@echo off
rem MSXPi launcher: MSX network check (if installed), msxpi-server, then openMSX.
cd /d "$MsxPiHome"
if exist "$MsxPiHome\msxpi-netcheck.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "$MsxPiHome\msxpi-netcheck.ps1"
powershell -NoProfile -Command "if (Get-CimInstance Win32_Process -Filter \"Name like 'python%%'\" | Where-Object { `$_.CommandLine -like '*msxpi-server.py*' }) { exit 1 }"
if not errorlevel 1 (
    start "msxpi-server" /D "$MsxPiHome" "$python" "$MsxPiHome\msxpi-server.py"
    ping -n 3 127.0.0.1 >nul
)
start "openMSX" /D "$OpenMsxDir" "$openmsxExe" -machine $Machine -ext MSXPi -ext ram4mb
"@ | Set-Content -Encoding ASCII "$MsxPiHome\start-openmsx.bat"
Ok "$MsxPiHome\start-openmsx.bat"
# Launchers of earlier versions of this script.
Remove-Item -Force "$MsxPiHome\start-msxpi.ps1", "$MsxPiHome\start-msxpi.bat", "$MsxPiHome\openmsx-msxpi.tcl" -ErrorAction SilentlyContinue

$desktop = [Environment]::GetFolderPath("Desktop")
try {
    $sh = (New-Object -ComObject WScript.Shell).CreateShortcut("$desktop\MSXPi.lnk")
    $sh.TargetPath = "$MsxPiHome\start-openmsx.bat"
    $sh.WorkingDirectory = $MsxPiHome
    $sh.WindowStyle = 7   # minimized: the batch window only starts the others
    if (Test-Path $openmsxExe) { $sh.IconLocation = $openmsxExe }
    $sh.Save()
    Ok "desktop shortcut"
} catch { Warn "desktop shortcut not created" }
# An earlier version put the shortcut on the all-users desktop (needs admin to remove).
Remove-Item -Force "$([Environment]::GetFolderPath('CommonDesktopDirectory'))\MSXPi.lnk" -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "Done. Start MSXPi with the MSXPi desktop icon, or $MsxPiHome\start-openmsx.bat" -ForegroundColor Green
Exit-Setup 0
