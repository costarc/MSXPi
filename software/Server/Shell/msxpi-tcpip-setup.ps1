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

    Give the MSX a route to the internet through Windows, for the MSXPi device
    under openMSX. The Windows counterpart of msxpi-tcpip-setup.sh.

    Run ONCE, as Administrator:

        powershell -ExecutionPolicy Bypass -File msxpi-tcpip-setup.ps1

    and to undo it:

        powershell -ExecutionPolicy Bypass -File msxpi-tcpip-setup.ps1 -Down

    Requires the OpenVPN TAP driver (tap-windows6). msxpi-server.py then opens
    the adapter itself - that part needs NO administrator rights, which is why
    this is a separate script rather than something the server does.

    Why NAT and not a bridge: bridging the MSX onto the LAN cannot work over
    WiFi, because an access point will not forward frames whose source MAC is
    not the associated station's. The MSX therefore sits on its own subnet
    behind NAT. It can reach the internet; nothing on the LAN can start a
    connection to it.
#>

[CmdletBinding()]
param(
    [string]$AdapterName = "",
    [string]$TapIp       = "192.168.99.1",
    [string]$MsxIp       = "192.168.99.2",
    [int]   $Prefix      = 24,
    # 576 is the IP minimum every implementation must support. The link runs at
    # roughly 18 KB/s, so a 1500-byte frame takes ~80 ms; a smaller MTU makes
    # TCP negotiate a smaller MSS and keeps the connection responsive.
    [int]   $Mtu         = 576,
    [string]$NatName     = "MSXPi",
    [switch]$Down
)

$ErrorActionPreference = "Stop"

# Plain one-line failures, like the shell script's. A bare `throw` prints a
# PowerShell stack trace around the message, which buries the one sentence the
# reader needs.
function Fail([string]$msg) {
    Write-Host "msxpi-tcpip-setup: $msg" -ForegroundColor Red
    exit 1
}

function Assert-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal $id
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Fail "must be run as Administrator (the address and the NAT need it; the server itself does not)"
    }
}

function Get-TapAdapter {
    # tap-windows6 reports its ComponentId as "tap0901" on some installs and
    # "root\tap0901" on others, so match the description Windows shows instead:
    # every build of the driver calls itself "TAP-Windows Adapter V9".
    $candidates = Get-NetAdapter -IncludeHidden |
        Where-Object { $_.InterfaceDescription -like "TAP-Windows Adapter*" }
    if ($AdapterName) {
        $candidates = $candidates | Where-Object { $_.Name -eq $AdapterName }
    }
    $tap = $candidates | Select-Object -First 1
    if (-not $tap) {
        Fail "no TAP-Windows adapter found. Install the OpenVPN TAP driver (tap-windows6), or pass -AdapterName if it has an unusual name."
    }
    return $tap
}

Assert-Admin
$tap = Get-TapAdapter
Write-Host "adapter: $($tap.Name)  [$($tap.InterfaceDescription)]"

if ($Down) {
    Get-NetNat -Name $NatName -ErrorAction SilentlyContinue |
        Remove-NetNat -Confirm:$false
    Get-NetIPAddress -InterfaceIndex $tap.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false
    # Put the adapter back the way a fresh TAP install leaves it, so it is
    # usable for whatever else it was installed for (an OpenVPN profile, say).
    Set-NetIPInterface -InterfaceIndex $tap.ifIndex -AddressFamily IPv4 -Dhcp Enabled -ErrorAction SilentlyContinue
    Set-NetIPInterface -InterfaceIndex $tap.ifIndex -Forwarding Disabled -ErrorAction SilentlyContinue
    Write-Host "torn down"
    exit 0
}

# --- The uplink, for reporting and for the DNS the MSX should use -----------
# Excluding the TAP itself: once it has an address it can carry a default
# route of its own, and then this would report the MSX's own subnet as the way
# out to the internet.
$uplink = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceIndex -ne $tap.ifIndex } |
    Sort-Object RouteMetric |
    Select-Object -First 1
if (-not $uplink) { Fail "no default route - is this machine on the network?" }
$uplinkAlias = (Get-NetAdapter -InterfaceIndex $uplink.InterfaceIndex).Name
Write-Host "uplink: $uplinkAlias"

# --- Address on the TAP -----------------------------------------------------
# DHCP first: a fresh TAP adapter comes up with DHCP enabled, and writing a
# static address into the persistent store while it is on fails with
# "Inconsistent parameters PolicyStore PersistentStore and Dhcp Enabled"
# (Windows error 87), which says nothing about DHCP being the problem.
Set-NetIPInterface -InterfaceIndex $tap.ifIndex -AddressFamily IPv4 -Dhcp Disabled -ErrorAction SilentlyContinue
Get-NetIPAddress -InterfaceIndex $tap.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false
New-NetIPAddress -InterfaceIndex $tap.ifIndex -IPAddress $TapIp -PrefixLength $Prefix | Out-Null
Set-NetIPInterface -InterfaceIndex $tap.ifIndex -NlMtuBytes $Mtu -ErrorAction SilentlyContinue
Write-Host "$($tap.Name) up: $TapIp/$Prefix mtu $Mtu"

# The firewall treats an unidentified network as Public and drops most
# forwarded traffic on it. The MSX subnet is ours and has no gateway of its
# own, so Windows can never identify it - say so explicitly.
Set-NetConnectionProfile -InterfaceIndex $tap.ifIndex -NetworkCategory Private -ErrorAction SilentlyContinue

# --- Forwarding and NAT -----------------------------------------------------
Set-NetIPInterface -InterfaceIndex $tap.ifIndex -Forwarding Enabled
Set-NetIPInterface -InterfaceIndex $uplink.InterfaceIndex -Forwarding Enabled

$prefixCidr = ($TapIp -replace '\.\d+$', '.0') + "/$Prefix"
$existing = Get-NetNat -ErrorAction SilentlyContinue
$mine = $existing | Where-Object { $_.Name -eq $NatName }
if ($mine) {
    $mine | Remove-NetNat -Confirm:$false
    $existing = Get-NetNat -ErrorAction SilentlyContinue
}
# WinNAT allows ONE NAT instance on most builds, and Docker Desktop, Hyper-V
# and WSL all take one. Say which one is in the way rather than failing with
# "the parameter is incorrect" from New-NetNat.
$clash = $existing | Where-Object { $_.InternalIPInterfaceAddressPrefix -ne $prefixCidr }
if ($clash) {
    Write-Host ""
    Write-Host "A NAT instance already exists and Windows generally allows only one:"
    $clash | Format-Table Name, InternalIPInterfaceAddressPrefix -AutoSize | Out-String | Write-Host
    Fail "remove it (Remove-NetNat -Name '$($clash[0].Name)') or stop what created it (Docker Desktop, Hyper-V), then run this again"
}
New-NetNat -Name $NatName -InternalIPInterfaceAddressPrefix $prefixCidr | Out-Null
Write-Host "NAT: $prefixCidr -> $uplinkAlias"

# --- What the MSX has to be told --------------------------------------------
$dns = (Get-DnsClientServerAddress -InterfaceIndex $uplink.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).ServerAddresses |
    Select-Object -First 1
if (-not $dns) { $dns = "1.1.1.1" }
Write-Host "dns: $dns"

Write-Host @"

Done. This is NOT persistent across reboots - re-run it, or wire it into Task
Scheduler once you are happy with the values.

Start msxpi-server.py (no administrator rights needed) and check it prints

    eth: TAP device $($tap.Name) up

If it says "TAP unavailable ... falling back to MockLink", something else has
the adapter open - an OpenVPN session using the same adapter will do that.

On the MSX, configure InterNestor Lite (there is no DHCP server on this
subnet, so the addresses are set by hand):

    inl ip d 0
    inl ip l $MsxIp
    inl ip m 255.255.255.0
    inl ip g $TapIp
    inl ip p $dns

or put the same lines, minus the leading "inl", in INL.CFG next to INL.COM and
they are applied at install time. Check with "inl s", then try a name lookup
from the MSX with "host google.com".
"@
