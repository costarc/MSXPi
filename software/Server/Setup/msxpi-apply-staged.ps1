<#
    MSXPi Interface - put a staged server update in place (Windows).

    "p update" on Windows runs msxpi-windows-setup.ps1 -Stage, which downloads
    the server files into <home>\staged and writes staged\READY last, so only
    a complete download is ever applied. Run while msxpi-server is NOT running:
    by start-openmsx.bat before it starts the server, and by "p restart" once
    the old server process has exited.

        msxpi-apply-staged.ps1 [-MsxPiHome C:\home\pi\msxpi] [-WaitPid <pid>]

    -WaitPid waits (up to 30 s) for that process to end first.
    Moves each staged file over the old one; a file that cannot be moved is
    kept in staged\ (with READY) for the next start.
#>
param(
    [string]$MsxPiHome = $PSScriptRoot,
    [int]$WaitPid = 0
)

if ($WaitPid) {
    try { Wait-Process -Id $WaitPid -Timeout 30 -ErrorAction Stop } catch { }
}

$staged = Join-Path $MsxPiHome "staged"
if (-not (Test-Path (Join-Path $staged "READY"))) { exit 0 }

$failed = 0
Get-ChildItem $staged -Recurse -File | Where-Object { $_.Name -ne "READY" } | ForEach-Object {
    $rel  = $_.FullName.Substring($staged.Length + 1)
    $dest = Join-Path $MsxPiHome $rel
    $moved = $false
    # A file can stay locked for a moment after the old server exits.
    for ($i = 0; $i -lt 5 -and -not $moved; $i++) {
        try {
            New-Item -ItemType Directory -Force (Split-Path -Parent $dest) | Out-Null
            Move-Item -Force $_.FullName $dest -ErrorAction Stop
            $moved = $true
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if ($moved) { Write-Host "ok   $rel" } else { Write-Host "FAIL $rel (kept staged)"; $failed++ }
}
if ($failed -eq 0) {
    Remove-Item -Recurse -Force $staged -ErrorAction SilentlyContinue
    Write-Host "MSXPi server update applied"
}
exit $failed
