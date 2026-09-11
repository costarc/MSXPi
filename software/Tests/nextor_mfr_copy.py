#!/usr/bin/env python3
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
debug set_bp 0x4010 {[pc_in_slot 2]} {r_lg "DSKIO "}
debug set_bp 0x4013 {[pc_in_slot 2]} {r_lg "DSKCHG"}
debug set_bp 0x4016 {[pc_in_slot 2]} {r_lg "GETDPB"}
'''

# Nextor calls GETDPB with whatever flags it has; carry set is what broke the
# old bare-RET GETDPB, but only when the timing lined up. Force carry on every
# entry so a GETDPB that hands it back fails deterministically.
FORCE_CARRY_TCL = r'''
debug set_bp 0x4016 {[pc_in_slot 2]} {reg f [expr {[reg f] | 1}]}
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
after time 28 { type [format %c 27]; after time 2 { type "\r"; after time 5 {
  r_snap prompt; after time 1 r_watch; r_run $::cmds } } }
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

    cmds = [] if a.only_back else [('to_msxpi', f'COPY B:{name} D:')]
    cmds += [('to_sd', f'COPY D:{name} B:ROUND.ROM'), ('dir', 'DIR B:')]
    tcl = work/'run.tcl'
    tcl.write_text('harness::init nextor_mfr_copy\n' + (TRACE_TCL if a.trace else '')
                   + ('' if a.natural_carry else FORCE_CARRY_TCL)
                   + 'set ::cmds {' + ' '.join('{%s {%s}}' % c for c in cmds) + '}\n' + STEPS_TCL)

    env = dict(os.environ, PYTHONPATH=str(SOFTWARE/'Server/Python/src'), REPRO_WORK=str(work),
               OPENMSX_USER_DATA=str(work/'share'), MSXPI_HARNESS_OUT=str(work/'result.txt'))
    cmd = ['/opt/openMSX/bin/openmsx', '-machine', 'Panasonic_FS-A1WSX', '-ext', 'MFRTest', '-ext', 'MSXPiTest',
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
    checks = [('D:'+name, work/'mounted/1_a.dsk', name)] if not a.only_back else []
    checks += [('B:ROUND.ROM', part, 'ROUND.ROM')]
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
        print(f"trace: {t.count('DSKIO')} DSKIO, {t.count('DSKCHG')} DSKCHG, {t.count('GETDPB')} GETDPB")
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
