<#
    MSXPi Interface
    Version 1.6
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
    of msxpi-setup.sh.

    Right-click > "Run with PowerShell" (it asks for administrator rights
    itself), or from a prompt:

        powershell -ExecutionPolicy Bypass -File msxpi-windows-setup.ps1

    Steps (each can be skipped with its -Skip switch):
      1. Python 3, 7-Zip (msxpi-server uses 7z.exe for zip/lzh/pma)  [winget]
      2. Python libraries: requests, fs, and a setuptools that still has pkg_resources
      3. C:\home\pi\msxpi with server, modules, ini files and disk images.
         The server hardcodes /home/pi/msxpi, which Windows resolves on the
         current drive - hence C:\home\pi\msxpi.
      4. openMSX from the costarc/MSXPi releases, plus MSXPi.xml and msxpibios.rom
      5. OpenVPN TAP driver (tap-windows6)
      6. start-msxpi.ps1 launcher and desktop shortcut. The launcher sets up
         the MSX network (msxpi-tcpip-setup.ps1) when it finds it missing.

    Re-running is safe: every step checks what is already there.
#>

[CmdletBinding()]
param(
    [string]$MsxPiHome   = "C:\home\pi\msxpi",
    # Default: an existing openMSX (PATH, Program Files, LocalAppData), else
    # a new install in $MsxPiHome\openMSX.
    [string]$OpenMsxDir  = "",
    # Local path or URL of an openMSX Windows zip; default is the newest
    # windows-vc-x64 build attached to a costarc/MSXPi release.
    [string]$OpenMsxZip  = "",
    [string]$Branch      = "master",
    [string]$Machine     = "Panasonic_FS-A1WSX",
    [string]$TapUrl      = "https://build.openvpn.net/downloads/releases/tap-windows-9.24.2-I601-Win10.exe",
    [switch]$SkipPython,
    [switch]$SkipMpv,
    [switch]$SkipOpenMsx,
    [switch]$SkipTap,
    [switch]$SkipNetwork
)

$ErrorActionPreference = "Stop"
$ProgressPreference    = "SilentlyContinue"   # Invoke-WebRequest is 10x slower with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Raw     = "https://raw.githubusercontent.com/costarc/MSXPi/$Branch/software"
$RawXml  = "https://raw.githubusercontent.com/costarc/openMSX/master/share/extensions/MSXPi.xml"
$Work    = Join-Path $env:TEMP "msxpi-setup"
New-Item -ItemType Directory -Force $Work | Out-Null

function Step([string]$msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Ok([string]$msg)   { Write-Host "    ok   $msg" -ForegroundColor Green }
function Warn([string]$msg) { Write-Host "    warn $msg" -ForegroundColor Yellow }
function Exit-Setup([int]$code) {
    # Started from Explorer the window closes on exit; keep it up to be read.
    Write-Host ""
    Read-Host "Press Enter to close" | Out-Null
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

# Try "import <modules>" and return whether it worked, with the last line of any
# error. Python writes warnings to stderr even when an import succeeds ("fs" prints
# a pkg_resources deprecation notice), and Windows PowerShell 5.1 turns any stderr
# line into a terminating error under $ErrorActionPreference = "Stop": so the
# preference is relaxed here and -W ignore silences the warnings at the source.
function Test-PyImport([string]$python, [string]$modules) {
    $old = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $out = & $python -W ignore -c "import $modules" 2>&1
        return [pscustomobject]@{ Ok = ($LASTEXITCODE -eq 0); Text = "$($out | Select-Object -Last 1)" }
    } finally {
        $ErrorActionPreference = $old
    }
}
function Update-Path {
    $env:Path = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [Environment]::GetEnvironmentVariable("Path", "User")
}

function Assert-Admin {
    # Relaunch elevated (one UAC prompt) instead of failing, so the script can
    # be started with a double-click or "Run with PowerShell". The bound
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
        Fail "administrator rights are needed (driver install and NAT) - the UAC prompt was declined"
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
        Fail "winget not found - install $what manually and run this again (or install 'App Installer' from the Store)"
    }
    & winget install --id $id -e --silent --scope machine --accept-package-agreements --accept-source-agreements
    # winget returns non-zero for "already installed"; the caller re-checks.
    Update-Path
}

function Install-Mpv {
    $mpvExe = "C:\Apps\mpv\mpv.exe"
    if (Test-Path $mpvExe) { Ok "mpv already installed"; return }

    Step "mpv"
    $api = Invoke-RestMethod "https://api.github.com/repos/mpv-distributions/mpv-windows-setup/releases/latest"
    $asset = $api.assets | Where-Object { $_.name -eq "mpv-setup-x86_64-$($api.tag_name).exe" } | Select-Object -First 1
    if (-not $asset) { Fail "could not find the x86_64 mpv installer" }
    $installer = Join-Path $Work $asset.name
    Get-File $asset.browser_download_url $installer | Out-Null
    & $installer /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /DIR=C:\Apps\mpv
    if (-not (Test-Path $mpvExe)) { Fail "mpv installation did not produce $mpvExe" }
    Ok "mpv installed in C:\Apps\mpv"
}

Assert-Admin
Write-Host "MSXPi Windows setup"
Write-Host "  home    : $MsxPiHome"
Write-Host "  openMSX : $(if ($OpenMsxDir) { $OpenMsxDir } else { 'auto-detect' })"

if (-not $SkipMpv) { Install-Mpv }

# --- 1. Python and 7-Zip ------------------------------------------------------
$python = $null
if (-not $SkipPython) {
    Step "Python 3"
    $python = Find-Python
    if (-not $python) {
        Install-Winget "Python.Python.3.12" "Python 3"
        $python = Find-Python
        if (-not $python) {
            foreach ($p in @("$env:ProgramFiles\Python312\python.exe", "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe")) {
                if (Test-Path $p) { $python = $p; break }
            }
        }
        if (-not $python) { Fail "Python install did not produce a working interpreter" }
    }
    Ok "$python ($(& $python --version 2>&1))"

    Step "7-Zip"
    # The server runs plain "7z.exe", so any copy on PATH will do.
    $onPath = Get-Command 7z.exe -ErrorAction SilentlyContinue
    if ($onPath) {
        Ok "$($onPath.Source) (already on PATH)"
    } else {
        $sevenZip = @("$env:ProgramFiles\7-Zip", "${env:ProgramFiles(x86)}\7-Zip") |
            Where-Object { Test-Path "$_\7z.exe" } | Select-Object -First 1
        if (-not $sevenZip) {
            Install-Winget "7zip.7zip" "7-Zip"
            $sevenZip = "$env:ProgramFiles\7-Zip"
            if (-not (Test-Path "$sevenZip\7z.exe")) { Fail "7-Zip not found in $sevenZip" }
        }
        $mp = [Environment]::GetEnvironmentVariable("Path", "Machine")
        [Environment]::SetEnvironmentVariable("Path", "$mp;$sevenZip", "Machine")
        Update-Path
        Ok "$sevenZip\7z.exe (added to PATH)"
    }

    # --- 2. Python libraries --------------------------------------------------
    Step "Python libraries"
    & $python -m pip install --upgrade pip --quiet
    # "fs" imports pkg_resources, which setuptools 81 and later no longer ships, and
    # a fresh Python 3.12+ has no setuptools at all - pip then fetches the newest one
    # for "fs" and the server dies on "import fs". Ask for one that still has it.
    # (pyfatfs, which the first version of this script installed, is not used.)
    & $python -m pip install --upgrade requests fs "setuptools<81" --quiet
    if ($LASTEXITCODE -ne 0) { Fail "pip install failed (see the message above; an error about long paths is fixed by enabling Windows long path support, or by installing Python from python.org into a short folder)" }
    $chk = Test-PyImport $python "requests, fs"
    if (-not $chk.Ok) { Fail "the Python libraries were installed but do not import: $($chk.Text)" }
    Ok "requests fs setuptools<81"
}

# --- 3. MSXPi home ------------------------------------------------------------
Step "MSXPi home $MsxPiHome"
foreach ($d in @($MsxPiHome, "$MsxPiHome\disks", "$MsxPiHome\native")) {
    New-Item -ItemType Directory -Force $d | Out-Null
}

$srv = "$Raw/Server/Python/src"
foreach ($f in @("msxpi-server.py", "msxpi_player.py", "mapper_detect.py", "msxpi_eth.py", "msxpi_gpio_native.py")) {
    Get-File "$srv/$f" "$MsxPiHome\$f" | Out-Null
}
foreach ($f in @("msxpi-JumperLeft.ini", "msxpi-JumperRight.ini", "msxpi-JumperRight_PCBV1.1Rev.0.ini")) {
    Get-File "$srv/$f" "$MsxPiHome\$f" -Optional | Out-Null
}
Get-File "$Raw/Server/Setup/msxpi-tcpip-setup.ps1" "$MsxPiHome\msxpi-tcpip-setup.ps1" | Out-Null

# Never overwrite msxpi.ini: it holds the user's API keys and PSET values.
if (-not (Test-Path "$MsxPiHome\msxpi.ini")) {
    Copy-Item "$MsxPiHome\msxpi-JumperLeft.ini" "$MsxPiHome\msxpi.ini"
    Ok "msxpi.ini created"
} else {
    Ok "msxpi.ini kept"
}

foreach ($f in @("msxpiboot.dsk", "tools.dsk", "blank.dsk")) {
    if (-not (Test-Path "$MsxPiHome\disks\$f")) {
        Get-File "$Raw/target/disks/$f" "$MsxPiHome\disks\$f" -Optional | Out-Null
    } else {
        Ok "$f kept"
    }
}

# --- 4. openMSX -----------------------------------------------------------------
# An existing openMSX is used where it is: -OpenMsxDir if given, else one on
# PATH or in the usual folders, else a fresh install under the MSXPi home.
$found = $null
if ($OpenMsxDir) {
    if (Test-Path "$OpenMsxDir\openmsx.exe") { $found = $OpenMsxDir }
} else {
    $cmd = Get-Command openmsx.exe -ErrorAction SilentlyContinue
    $candidates = @()
    if ($cmd) { $candidates += Split-Path $cmd.Source }
    $candidates += "$env:ProgramFiles\openMSX", "${env:ProgramFiles(x86)}\openMSX",
                   "$env:LOCALAPPDATA\openMSX", "$MsxPiHome\openMSX"
    $found = $candidates | Where-Object { $_ -and (Test-Path "$_\openmsx.exe") } | Select-Object -First 1
    $OpenMsxDir = if ($found) { $found } else { "$MsxPiHome\openMSX" }
}
$openmsxExe = Join-Path $OpenMsxDir "openmsx.exe"

if (-not $SkipOpenMsx) {
    Step "openMSX"
    if ($found -and -not $OpenMsxZip) {
        # Stock openMSX has no MSXPi device; the name is compiled into builds that do.
        $bin = [Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($openmsxExe))
        if ($bin.Contains("MSXPi")) {
            Ok "found $openmsxExe"
        } else {
            Warn "found $openmsxExe, but it does not look like it has the MSXPi device - pass -OpenMsxZip to install the MSXPi build"
        }
    }
    if (-not $found -or $OpenMsxZip) {
        if (-not $OpenMsxZip) {
            $rels = Invoke-RestMethod "https://api.github.com/repos/costarc/MSXPi/releases?per_page=50" -UseBasicParsing
            $asset = $rels | Sort-Object { [datetime]$_.published_at } -Descending |
                ForEach-Object { $_.assets } |
                Where-Object { $_.name -like "openmsx-*windows-vc-x64-bin*.zip" } |
                Select-Object -First 1
            if (-not $asset) { Fail "no openMSX Windows build found in the costarc/MSXPi releases; pass -OpenMsxZip" }
            $OpenMsxZip = $asset.browser_download_url
        }
        $zip = Join-Path $Work "openmsx.zip"
        if ($OpenMsxZip -match '^https?://') {
            Write-Host "    downloading $OpenMsxZip"
            Get-File $OpenMsxZip $zip | Out-Null
        } else {
            Copy-Item $OpenMsxZip $zip -Force
        }

        # Release assets are zipped twice (name.zip.zip), so unpack until an
        # openmsx.exe shows up.
        $x = Join-Path $Work "openmsx-x"
        Remove-Item -Recurse -Force $x -ErrorAction SilentlyContinue
        Expand-Archive $zip $x -Force
        for ($i = 0; $i -lt 3 -and -not (Get-ChildItem $x -Recurse -Filter openmsx.exe); $i++) {
            $inner = Get-ChildItem $x -Recurse -Filter *.zip | Select-Object -First 1
            if (-not $inner) { break }
            $next = "$x-$i"
            Expand-Archive $inner.FullName $next -Force
            $x = $next
        }
        $exe = Get-ChildItem $x -Recurse -Filter openmsx.exe | Select-Object -First 1
        if (-not $exe) { Fail "openmsx.exe not found inside $OpenMsxZip" }

        New-Item -ItemType Directory -Force $OpenMsxDir | Out-Null
        Copy-Item "$($exe.DirectoryName)\*" $OpenMsxDir -Recurse -Force
        Ok "installed to $OpenMsxDir"
    }

    # Newest extension definition and BIOS, so the ROM's sha1 is one the XML knows.
    New-Item -ItemType Directory -Force "$OpenMsxDir\share\extensions", "$OpenMsxDir\share\systemroms" | Out-Null
    Get-File $RawXml "$OpenMsxDir\share\extensions\MSXPi.xml" -Optional | Out-Null
    Get-File "$Raw/target/msxpibios.rom" "$OpenMsxDir\share\systemroms\msxpibios.rom" | Out-Null
    Copy-Item "$OpenMsxDir\share\systemroms\msxpibios.rom" "$MsxPiHome\msxpibios.rom" -Force
}

# --- 5. TAP driver and network ---------------------------------------------------
function Get-Tap {
    Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -like "TAP-Windows Adapter*" } |
        Select-Object -First 1
}

if (-not $SkipTap) {
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
}

# The MSX network (TAP address + NAT) is not configured here: the launcher
# checks it each time MSXPi starts and asks for elevation only when it is
# missing. Remove the boot-time task an earlier version of this script made.
Unregister-ScheduledTask -TaskName "MSXPi TCPIP Setup" -Confirm:$false -ErrorAction SilentlyContinue

# --- 6. Launcher ------------------------------------------------------------------
Step "Launcher"
if (-not $python) { $python = Find-Python }
if (-not $python) { $python = "python" }
@"
machine $Machine
ext MSXPi
ext ram4mb
bind F12 cycle videosource
set speed 100
"@ | Set-Content -Encoding ASCII "$MsxPiHome\openmsx-msxpi.tcl"

# Single-quoted template, placeholders filled in below: no escaping of the
# launcher's own $variables.
$launcher = @'
# MSXPi launcher: MSX network check, msxpi-server, then openMSX.
$ErrorActionPreference = "Continue"
$home_   = '@HOME@'
$python  = '@PYTHON@'
$openmsx = '@OPENMSX@'
$checkNet = @CHECKNET@

if ($checkNet) {
    # Reading the NAT and the address needs no administrator rights; only
    # (re)creating them does, so UAC appears only when something is missing.
    $tap = Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceDescription -like "TAP-Windows Adapter*" } | Select-Object -First 1
    $nat = Get-NetNat -Name MSXPi -ErrorAction SilentlyContinue
    $ip  = if ($tap) { Get-NetIPAddress -InterfaceIndex $tap.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                       Where-Object { $_.IPAddress -eq "192.168.99.1" } }
    if ($tap -and -not ($nat -and $ip)) {
        Write-Host "MSX network not configured - requesting administrator rights to set it up"
        try {
            Start-Process powershell.exe -Verb RunAs -Wait -ArgumentList @(
                "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$home_\msxpi-tcpip-setup.ps1`"")
        } catch {
            Write-Host "Skipped: MSXPi runs, but the MSX has no TCP/IP."
        }
    }
}

$running = Get-CimInstance Win32_Process -Filter "Name like 'python%'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -like "*msxpi-server.py*" }
if (-not $running) {
    Start-Process $python -ArgumentList "`"$home_\msxpi-server.py`"" -WorkingDirectory $home_
    Start-Sleep -Seconds 2
}
if (-not (Get-Process openmsx -ErrorAction SilentlyContinue)) {
    Start-Process $openmsx -ArgumentList "-script", "`"$home_\openmsx-msxpi.tcl`"" -WorkingDirectory (Split-Path $openmsx)
}
'@
$launcher = $launcher.Replace('@HOME@', $MsxPiHome).Replace('@PYTHON@', $python).
    Replace('@OPENMSX@', $openmsxExe).Replace('@CHECKNET@', $(if ($SkipNetwork) { '$false' } else { '$true' }))
Set-Content -Encoding UTF8 -Path "$MsxPiHome\start-msxpi.ps1" -Value $launcher
Remove-Item -Force "$MsxPiHome\start-msxpi.bat" -ErrorAction SilentlyContinue
Ok "$MsxPiHome\start-msxpi.ps1"

# A shortcut runs powershell.exe directly, so it starts on double-click and
# is not subject to the execution policy.
$lnk = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "MSXPi.lnk"
try {
    $sh = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
    $sh.TargetPath = "powershell.exe"
    $sh.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$MsxPiHome\start-msxpi.ps1`""
    $sh.WorkingDirectory = $MsxPiHome
    if (Test-Path $openmsxExe) { $sh.IconLocation = $openmsxExe }
    $sh.Save()
    Ok "desktop shortcut"
} catch { Warn "desktop shortcut not created" }

Write-Host ""
Write-Host "Done. Start MSXPi with the MSXPi desktop icon." -ForegroundColor Green
Exit-Setup 0
