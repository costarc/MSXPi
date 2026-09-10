#!/usr/bin/env python3
"""Isolated openMSX copy/fault regression. Requires an MSXPi-enabled emulator."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import socket
import struct
import subprocess
import time

SOFTWARE = Path(__file__).resolve().parents[1]


def extract(image, name):
    data = image.read_bytes()
    u16 = lambda n: struct.unpack_from('<H', data, n)[0]
    bps, spc, reserved, fats, entries, spf = u16(11), data[13], u16(14), data[16], u16(17), u16(22)
    fat = data[reserved*bps:(reserved+spf)*bps]
    root = (reserved + fats*spf)*bps
    start = root + ((entries*32+bps-1)//bps)*bps
    stem, ext = name.upper().split('.')
    wanted = (stem.ljust(8)+ext.ljust(3)).encode()
    for i in range(entries):
        entry = data[root+i*32:root+(i+1)*32]
        if entry[:11] != wanted:
            continue
        cluster = struct.unpack_from('<H', entry, 26)[0]
        size = struct.unpack_from('<I', entry, 28)[0]
        result, seen = bytearray(), set()
        while cluster < 0xff8:
            assert cluster >= 2 and cluster not in seen, 'invalid FAT chain'
            seen.add(cluster)
            pos = start+(cluster-2)*spc*bps
            result += data[pos:pos+spc*bps]
            pos = cluster*3//2
            value = int.from_bytes(fat[pos:pos+2], 'little')
            cluster = value >> 4 if cluster & 1 else value & 0xfff
        return bytes(result[:size])
    raise AssertionError(f'{name} missing from {image}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom', type=Path, required=True)
    parser.add_argument('--client', type=Path, required=True)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--direction', choices=['download', 'upload', 'dos-copy'], default='download')
    parser.add_argument('--fault', choices=['none', 'once', 'always', 'sector-info'], default='none')
    parser.add_argument('--nextor-mapper', action='store_true', help='512 KiB RAM in boot-controller subslot 2, ROM in subslot 3')
    parser.add_argument('--nextor-hd', type=Path, help='Isolated Nextor/Sunrise boot image; COPY A:INPUT.ROM C:OUTPUT.ROM')
    parser.add_argument('--openmsx', default='/opt/openMSX/bin/openmsx')
    parser.add_argument('--boot-disk', type=Path, default=Path('/home/pi/msxpi/disks/msxpiboot.dsk'))
    parser.add_argument('--data-disk', type=Path, default=Path('/home/pi/msxpi/disks/tools.dsk'))
    args = parser.parse_args()
    if args.direction != 'download' and args.fault != 'none':
        parser.error('disk-write fault modes apply to download tests')
    args.output.mkdir(parents=True, exist_ok=True)
    work = args.output.resolve()
    # Refuse to share the stateful protocol with an existing server.
    with socket.socket() as probe:
        if probe.connect_ex(('127.0.0.1', 5000)) == 0:
            raise RuntimeError('Port 5000 is already in use')
    for src, dest in [(args.boot_disk, 'a.dsk'), (args.data_disk, 'b.dsk'), (args.input, 'INPUT.ROM')]:
        shutil.copyfile(src, work/dest)
    subprocess.run(['python3', str(SOFTWARE/'dsktool.py'), 'copy', str(args.client.resolve()),
                    str(work/'a.dsk')+':PCOPY.COM'], check=True, stdout=subprocess.DEVNULL)
    if args.direction in ('upload', 'dos-copy'):
        subprocess.run(['python3', str(SOFTWARE/'dsktool.py'), 'copy', str(work/'INPUT.ROM'),
                        str(work/'b.dsk')+':INPUT.ROM'], check=True, stdout=subprocess.DEVNULL)
    (work/'msxpi.ini').write_text(f'var PATH={work}\nvar DriveA={work}/a.dsk\nvar DriveB={work}/b.dsk\nvar WIDTH=80\n')
    # Execute the actual server source with test-only paths and fault injection.
    # No changes to the installed server, its config, or its served disks.
    server = (SOFTWARE/'Server/Python/src/msxpi-server.py').read_text(encoding='utf-8-sig')
    server = server.replace('MSXPIHOME = "/home/pi/msxpi"', f'MSXPIHOME = {str(work)!r}')
    server = server.replace('os.path.join("/tmp/msxpi", "mounted")', repr(str(work/'mounted')))
    for name in ['pcopy_session.bin', 'pcopy_state.txt', 'pcopy_put_state.txt']:
        server = server.replace('/tmp/'+name, str(work/name))
    server = server.replace('def pcopy(msxcmd="pcopy"):', 'def pcopy(msxcmd="pcopy"):\n    globals()["_test_copy_started"] = True')
    begin = server.index('def recvdata2(')
    end = server.index('\ndef ', begin+1)
    part = server[begin:end]
    length = 5 if args.fault == 'sector-info' else 512
    condition = 'False' if args.fault == 'none' else 'True'
    if args.fault == 'once':
        condition = 'not globals().get("_test_faults", 0)'
    injection = f'''        if length == {length} and globals().get('_test_copy_started') and ({condition}):
            globals()['_test_faults'] = globals().get('_test_faults', 0) + 1
            local_sum ^= 1
            print('TEST CHECKSUM FAULT', globals()['_test_faults'], flush=True)
'''
    part = part.replace('        # --- Send local checksum back ---', injection+'        # --- Send local checksum back ---')
    server = server[:begin]+part+server[end:]
    server_path = work/'server.py'
    server_path.write_text(server)
    share = work/'share/extensions'
    share.mkdir(parents=True, exist_ok=True)
    extension = (SOFTWARE/'openMSX/share/extensions/MSXPi.xml').read_text()
    extension = re.sub(r'<sha1>.*?</sha1>', '<sha1>'+hashlib.sha1(args.rom.read_bytes()).hexdigest()+'</sha1>', extension)
    extension = re.sub(r'<filename>.*?</filename>', '<filename>'+str(args.rom.resolve())+'</filename>', extension)
    (share/'MSXPiTest.xml').write_text(extension)
    script = work/'test.tcl'
    script.write_text('''harness::init pcopy
proc watch {} {
    if {[string match "*Abort*Retry*" [harness::screen_text]]} {
        harness::fail copy "DOS disk error"
        harness::done
        return
    }
    after realtime 0.5 watch
}
after realtime 0.5 watch
harness::at_dos_prompt {
    harness::run_cmd "B:" 1000 {
        harness::run_cmd "A:pcopy INPUT.ROM OUTPUT.ROM" 10000 {
            harness::assert_screen_contains copy "File copied successfully"
            harness::run_cmd "dir" 1000 { harness::done }
        }
    }
} 10000
''')
    if args.direction == 'upload':
        script.write_text(script.read_text().replace(
            'A:pcopy INPUT.ROM OUTPUT.ROM', 'A:pcopy B:INPUT.ROM OUTPUT.ROM').replace(
            'File copied successfully', 'File copied to'))
    if args.direction == 'dos-copy':
        script.write_text(script.read_text().replace(
            'A:pcopy INPUT.ROM OUTPUT.ROM" 10000', 'COPY INPUT.ROM OUTPUT.ROM" 40000').replace(
            'harness::assert_screen_contains copy "File copied successfully"',
            '# Destination bytes are verified from the disk image below.'))
    env = dict(os.environ, PYTHONPATH=str(SOFTWARE/'Server/Python/src'),
               OPENMSX_USER_DATA=str(work/'share'), MSXPI_HARNESS_OUT=str(work/'result.txt'))
    machine = 'Panasonic_FS-A1WSX'
    hardware = ['-ext', 'ram4mb', '-ext', 'MSXPiTest']
    if args.nextor_hd:
        if args.direction != 'dos-copy' or args.fault != 'none':
            parser.error('--nextor-hd requires --direction dos-copy without faults')
        machine = 'Philips_NMS_8245'  # 128 KiB mapper required by Nextor
        shutil.copyfile(args.nextor_hd, work/'nextor.dsk')
        nextor = Path('/opt/openMSX/share/extensions/SunriseIDE_Nextor.xml').read_text()
        nextor = re.sub(r'<rom>.*?</rom>', '<rom><filename>/opt/openMSX/share/systemroms/extensions/Nextor-2.1.0.SunriseIDE.emulators.ROM</filename></rom>', nextor, flags=re.S)
        if args.nextor_mapper:
            nextor = nextor.replace('<primary slot="any">', '<primary slot="1">').replace('<secondary slot="any">', '<secondary slot="3">')
            nextor = nextor.replace('</primary>', '<secondary slot="2"><MemoryMapper id="Boot controller RAM"><mem base="0x0000" size="0x10000"/><size>512</size></MemoryMapper></secondary></primary>')
        (share/'NextorTest.xml').write_text(nextor)
        hardware = ['-ext', 'NextorTest', '-ext', 'MSXPiTest']
        # diskmanipulator in this openMSX build cannot edit standard MBR images.
        # Edit the first FAT12 partition offline, retaining the partition table.
        hd = bytearray((work/'nextor.dsk').read_bytes())
        first = int.from_bytes(hd[454:458], 'little')*512
        size = int.from_bytes(hd[458:462], 'little')*512
        assert hd[510:512] == b'\x55\xaa' and first and size, 'Use a standard MBR boot image'
        partition = work/'nextor-partition.dsk'
        partition.write_bytes(hd[first:first+size])
        subprocess.run(['python3', str(SOFTWARE/'dsktool.py'), 'copy', str(work/'INPUT.ROM'),
                        str(partition)+':INPUT.ROM'], check=True, stdout=subprocess.DEVNULL)
        hd[first:first+size] = partition.read_bytes()
        (work/'nextor.dsk').write_bytes(hd)
        script.write_text(script.read_text().replace(
            '"B:"', '"A:"').replace('COPY INPUT.ROM OUTPUT.ROM', 'COPY A:INPUT.ROM C:OUTPUT.ROM').replace(
            'harness::run_cmd "dir" 1000 { harness::done }',
            'harness::run_cmd "COPY C:OUTPUT.ROM A:ROUND.ROM" 40000 { harness::run_cmd "DIR C:OUTPUT.ROM" 1000 { harness::done } }'))
        script.write_text(f'hda {{{work}/nextor.dsk}}\n' + script.read_text())
    start = time.monotonic()
    with (work/'server.log').open('w') as log, (work/'openmsx.log').open('w') as emulog:
        process = subprocess.Popen(['python3', '-u', str(server_path)], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            time.sleep(1)
            assert process.poll() is None, 'server failed to start'
            subprocess.run([args.openmsx, '-machine', machine, *hardware, '-command', 'set renderer none', '-command', 'set throttle off',
                            '-script', str(SOFTWARE/'UNAPI/harness/lib/harness.tcl'), '-script', str(script)],
                           env=env, stdout=emulog, stderr=subprocess.STDOUT, timeout=900, check=True)
        finally:
            process.terminate()
            try:
                process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
    elapsed = time.monotonic()-start
    result = (work/'result.txt').read_text()
    logs = (work/'server.log').read_text()
    count = logs.count('TEST CHECKSUM FAULT')
    if args.fault in ('always', 'sector-info'):
        assert 'DOS disk error' in result and count == 3, (result, count)
        if args.fault == 'sector-info':
            assert '-> dskiowrs' not in logs.split('-> pcopy init', 1)[1]
        print(f'PASS: {args.fault}: exactly 3 attempts, DOS error propagated ({elapsed:.1f}s)')
    else:
        assert 'RESULT PASS' in result, result
        output = (work/'OUTPUT.ROM').read_bytes() if args.direction == 'upload' else extract(work/('mounted/1_a.dsk' if args.nextor_hd else 'mounted/2_b.dsk'), 'OUTPUT.ROM')
        assert output == args.input.read_bytes(), 'destination differs from source'
        assert count == (1 if args.fault == 'once' else 0), count
        if args.nextor_hd:
            partition.write_bytes((work/'nextor.dsk').read_bytes()[first:first+size])
            assert extract(partition, 'ROUND.ROM') == args.input.read_bytes(), 'Nextor return copy differs'
            print('PASS: Nextor cross-controller return copy is byte-identical')
        print(f'PASS: {len(output)} bytes identical; {count} injected faults; SHA256 {hashlib.sha256(output).hexdigest()} ({elapsed:.1f}s)')


if __name__ == '__main__':
    main()
