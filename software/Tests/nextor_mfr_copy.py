#!/usr/bin/env python3
# MSXPi Interface
# Version 1.6
# ------------------------------------------------------------------------------
# MIT License
#
# Copyright (c) 2015-2026 Ronivon Costa
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
# ------------------------------------------------------------------------------

"""Nextor cross-device COPY regression: MegaFlashROM SCC+ SD + MSXPi.

Topology matches the reported failure: Panasonic_FS-A1WSX, MegaFlashROM
SCC+ SD in slot 1 (Nextor boots from its flash, the SD auto-maps to B:),
MSXPi in slot 2 (D:, legacy driver). The default test runs

    COPY B:ALESTE.ROM D:            (SD -> MSXPi)
    COPY D:ALESTE.ROM B:ROUND.ROM   (MSXPi -> SD)

and checks both copies byte-for-byte. Before the GETDPB fix the second COPY
failed with "Not a DOS disk reading drive D:" whenever Nextor re-validated
the drive mid-copy (DSKCHG "unknown" -> boot sector -> GETDPB with carry set).

Run inside WSL with the MSXPi-enabled openMSX in /opt/openMSX and port 5000
free (stop any other msxpi-server first):

    python3 Tests/nextor_mfr_copy.py /tmp/mfr --sd nextor-mbr.dsk
    python3 Tests/nextor_mfr_copy.py /tmp/mfr --sd nextor-mbr.dsk --preload --only-back --trace

--sd is any MBR image whose first partition is FAT12 (e.g. a Nextor
Sunrise HD image); the input file is written into that partition.

Never use "set throttle off" here: the server answers in real time, so an
unthrottled MSX burns emulated seconds polling and every timeout is wrong.
Speed 250% is the tested maximum.
"""
import argparse
import hashlib
import os
import re
import shutil
import socket
import subprocess
import sys
import time
from pathlib import Path

TESTS = Path(__file__).resolve().parent
SOFTWARE = TESTS.parent
sys.path.insert(0, str(TESTS))
from pcopy_emulator import extract  # noqa: E402

OPENMSX_SHARE = Path('/opt/openMSX/share')

# Driver entry points are fixed by the DOS1 kernel jump table, so the trace
# does not need updating when msxpi-driver.mac code moves.
TRACE_TCL = r'''
set ::lg [open "$::env(REPRO_WORK)/trace.log" w]
fconfigure $::lg -buffering line
proc r_h4 {v} { format %04x $v }
proc r_lg {tag} {
  puts $::lg "$tag af=[r_h4 [reg af]] bc=[r_h4 [reg bc]] de=[r_h4 [reg de]] hl=[r_h4 [reg hl]] sp=[r_h4 [reg sp]] t=[format %.2f [machine_info time]]"
}
debug set_bp 0x4010 {[pc_in_slot PISLOT]} {r_lg "DSKIO "}
debug set_bp 0x4013 {[pc_in_slot PISLOT]} {r_lg "DSKCHG"}
debug set_bp 0x4016 {[pc_in_slot PISLOT]} {r_lg "GETDPB"}
'''

# Nextor calls GETDPB with whatever flags it has; carry set is what broke the
# old bare-RET GETDPB, but only when the timing lined up. Force carry on every
# entry so a GETDPB that hands it back fails deterministically.
FORCE_CARRY_TCL = r'''
debug set_bp 0x4016 {[pc_in_slot PISLOT]} {reg f [expr {[reg f] | 1}]}
'''

# Leave MultiMente (AUTOEXEC on the MFR flash): ESC, then RETURN.
# Commands are chained on the DOS prompt, not on fixed delays.
STEPS_TCL = r'''
proc r_snap {n} { catch {screenshot -raw "$::env(REPRO_WORK)/$n.png"}
  set f [open "$::env(REPRO_WORK)/$n.txt" w]; puts $f [harness::screen_text]; close $f }
proc r_watch {} {
  if {[string match "*Abort*Retry*" [harness::screen_text]]} {
    r_snap error; harness::fail copy "DOS disk error"; harness::done; return }
  after time 1 r_watch }
proc r_run {cmds} {
  if {[llength $cmds] == 0} { harness::pass copy; harness::done; return }
  set c [lindex $cmds 0]; set n [lindex $c 0]
  harness::run_cmd [lindex $c 1] 900 [list r_next $n [lrange $cmds 1 end]] }
proc r_next {n rest} { r_snap $n; r_run $rest }
proc r_start {} { r_snap prompt; after time 1 r_watch; r_run $::cmds }
if {$::nextor_mm} {
  after time 28 { type [format %c 27]; after time 2 { type "\r"; after time 5 r_start } }
} else {
  # MSXPi's own DOS1 boot: no MultiMente, and an ESC here would abort the
  # MSXPi transfer that is loading COMMAND.COM.
  harness::wait_for "A:" 60 { after time 3 r_start }
}
'''


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('work', type=Path, help='scratch directory for disks, logs and screens')
    ap.add_argument('--sd', type=Path, required=True, help='MBR image, first partition FAT12')
    ap.add_argument('--rom', type=Path, default=SOFTWARE/'target/msxpibios.rom')
    ap.add_argument('--input', type=Path, default=Path('/mnt/c/tmp/ALESTE.ROM'))
    ap.add_argument('--preload', action='store_true', help='also put the file on D: beforehand')
    ap.add_argument('--only-back', action='store_true', help='only COPY D: -> B: (implies --preload)')
    ap.add_argument('--trace', action='store_true', help='log driver entry points to trace.log')
    ap.add_argument('--natural-carry', action='store_true',
                    help='do not force carry on GETDPB entry (failure becomes timing-dependent)')
    ap.add_argument('--machine', default='Panasonic_FS-A1WSX',
                    help='e.g. Sony_HB-F9P (no floppy: SD becomes A:, MSXPi C:/D:)')
    ap.add_argument('--sd-drive', default='B', help='drive letter Nextor gives the SD')
    ap.add_argument('--pi-drive', default='D', help='drive letter of MSXPi unit 0')
    ap.add_argument('--pre', action='append', default=[],
                    help='DOS command to run before the copies (repeatable), e.g. "MAPDRV A: 1 2"')
    ap.add_argument('--extra', action='append', type=Path, default=[],
                    help='extra file to put on the MSXPi disk (repeatable), e.g. Tests/p1test/P1TEST.COM')
    ap.add_argument('--no-copy', action='store_true', help='run only the --pre commands')
    ap.add_argument('--no-mfr', action='store_true',
                    help='no MegaFlashROM: MSXPi boots its own MSX-DOS 1 kernel (A:/B:)')
    ap.add_argument('--tcl', type=Path, help='extra Tcl appended to the run script (breakpoints etc.)')
    ap.add_argument('--gui', action='store_true', help='show the openMSX window')
    ap.add_argument('--speed', type=int, default=250)
    ap.add_argument('--timeout', type=int, default=1800)
    a = ap.parse_args()
    if a.only_back:
        a.preload = True

    work = a.work.resolve()
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    with socket.socket() as s:
        if s.connect_ex(('127.0.0.1', 5000)) == 0:
            raise SystemExit('port 5000 busy - stop the other msxpi-server first')

    dsktool = [sys.executable, str(SOFTWARE/'dsktool.py'), 'copy']
    name = 'ALESTE.ROM'
    shutil.copyfile(a.input, work/'INPUT.ROM')
    want = (work/'INPUT.ROM').read_bytes()

    # MSXPi D: (the server's DriveA)
    shutil.copyfile(SOFTWARE/'target/disks/msxpiboot.dsk', work/'a.dsk')
    shutil.copyfile(SOFTWARE/'target/disks/msxpiboot.dsk', work/'b.dsk')
    for f in a.extra:
        subprocess.run(dsktool + [str(f), f'{work}/a.dsk:{f.name.upper()}'], check=True, stdout=subprocess.DEVNULL)
    if a.preload:
        subprocess.run(dsktool + [str(work/'INPUT.ROM'), f'{work}/a.dsk:{name}'], check=True, stdout=subprocess.DEVNULL)

    # SD card: file into the first partition, partition table kept.
    hd = bytearray(a.sd.read_bytes())
    first = int.from_bytes(hd[454:458], 'little')*512
    size = int.from_bytes(hd[458:462], 'little')*512
    assert hd[510:512] == b'\x55\xaa' and first and size, '--sd must be an MBR image'
    part = work/'sdpart.dsk'
    part.write_bytes(hd[first:first+size])
    subprocess.run(dsktool + [str(work/'INPUT.ROM'), f'{part}:{name}'], check=True, stdout=subprocess.DEVNULL)
    hd[first:first+size] = part.read_bytes()
    sd = work/'SDcard1.sdc'
    sd.write_bytes(hd)

    (work/'msxpi.ini').write_text(f'var PATH={work}\nvar DriveA={work}/a.dsk\nvar DriveB={work}/b.dsk\nvar WIDTH=80\n')
    srv = (SOFTWARE/'Server/Python/src/msxpi-server.py').read_text(encoding='utf-8-sig')
    srv = srv.replace('MSXPIHOME = "/home/pi/msxpi"', f'MSXPIHOME = {str(work)!r}')
    srv = srv.replace('os.path.join("/tmp/msxpi", "mounted")', repr(str(work/'mounted')))
    (work/'server.py').write_text(srv)

    ext = work/'share/extensions'
    ext.mkdir(parents=True)
    x = (SOFTWARE/'openMSX/share/extensions/MSXPi.xml').read_text()
    x = re.sub(r'<sha1>.*?</sha1>', '<sha1>'+hashlib.sha1(a.rom.read_bytes()).hexdigest()+'</sha1>', x)
    x = re.sub(r'<filename>.*?</filename>', '<filename>'+str(a.rom.resolve())+'</filename>', x)
    (ext/'MSXPiTest.xml').write_text(x)
    m = (OPENMSX_SHARE/'extensions/MegaFlashROM_SCC+_SD.xml').read_text()
    m = m.replace('<filename>SDcard1.sdc</filename>', f'<filename>{sd}</filename>')
    m = m.replace('<sramname>megaflashromsccplussd.sram</sramname>', f'<sramname>{work}/mfr.sram</sramname>')
    (ext/'MFRTest.xml').write_text(m)

    sdd, pid = a.sd_drive.rstrip(':').upper(), a.pi_drive.rstrip(':').upper()
    cmds = [(f'pre{i}', c) for i, c in enumerate(a.pre)] + [('drvinfo', 'DRVINFO')]
    if not a.no_copy:
        cmds += [] if a.only_back else [('to_msxpi', f'COPY {sdd}:{name} {pid}:')]
        cmds += [('to_sd', f'COPY {pid}:{name} {sdd}:ROUND.ROM'), ('dir', f'DIR {sdd}:')]
    tcl = work/'run.tcl'
    slot = '1' if a.no_mfr else '2'   # MSXPi takes the first free cartridge slot
    tcl.write_text('harness::init nextor_mfr_copy\n'
                   + f'set ::nextor_mm {0 if a.no_mfr else 1}\n'
                   + (TRACE_TCL if a.trace else '').replace('PISLOT', slot)
                   + ('' if a.natural_carry else FORCE_CARRY_TCL).replace('PISLOT', slot)
                   + (a.tcl.read_text() + chr(10) if a.tcl else '')
                   + 'set ::cmds {' + ' '.join('{%s {%s}}' % c for c in cmds) + '}\n' + STEPS_TCL)

    env = dict(os.environ, PYTHONPATH=str(SOFTWARE/'Server/Python/src'), REPRO_WORK=str(work),
               OPENMSX_USER_DATA=str(work/'share'), MSXPI_HARNESS_OUT=str(work/'result.txt'))
    cmd = ['/opt/openMSX/bin/openmsx', '-machine', a.machine, *([] if a.no_mfr else ['-ext', 'MFRTest']), '-ext', 'MSXPiTest',
           '-command', f'set speed {a.speed}']
    if not a.gui:
        cmd += ['-command', 'set renderer none']
    cmd += ['-script', str(SOFTWARE/'UNAPI/harness/lib/harness.tcl'), '-script', str(tcl)]
    t0 = time.monotonic()
    with open(work/'server.log', 'w') as log, open(work/'openmsx.log', 'w') as elog:
        srvp = subprocess.Popen([sys.executable, '-u', str(work/'server.py')], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            time.sleep(1)
            assert srvp.poll() is None, 'server failed to start'
            subprocess.run(cmd, env=env, stdout=elog, stderr=subprocess.STDOUT, timeout=a.timeout)
        finally:
            srvp.terminate()
            try:
                srvp.wait(timeout=3)
            except subprocess.TimeoutExpired:
                srvp.kill()
    result = (work/'result.txt').read_text() if (work/'result.txt').exists() else 'NO RESULT'
    print(result.split('--- final screen ---')[0].strip())
    print(f'elapsed {time.monotonic()-t0:.0f}s')

    ok = 'RESULT PASS' in result
    part.write_bytes(sd.read_bytes()[first:first+size])
    checks = [(f'{pid}:'+name, work/'mounted/1_a.dsk', name)] if not a.only_back else []
    checks += [(f'{sdd}:ROUND.ROM', part, 'ROUND.ROM')]
    if a.no_copy:
        checks = []
    for label, img, fn in checks:
        try:
            got = extract(img, fn) if img.exists() else b''
        except AssertionError as e:
            got, label = b'', f'{label} ({e})'
        same = got == want
        ok &= same
        print(f"{'PASS' if same else 'FAIL'}: {label} {len(got)} bytes {hashlib.sha256(got).hexdigest()[:16]}")
    if a.trace:
        t = (work/'trace.log').read_text()
        p1 = sum(1 for l in t.splitlines() if l.startswith('DSKIO') and 0x3E <= int(l.split('hl=')[1][:2], 16) <= 0x7F)
        print(f"trace: {t.count('DSKIO')} DSKIO ({p1} with a page-1 start address), "
              f"{t.count('DSKCHG')} DSKCHG, {t.count('GETDPB')} GETDPB")
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
