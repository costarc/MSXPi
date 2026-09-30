"""Run with: python3 -m unittest discover -s software/Server/Python/tests -p test_nitros.py"""
import os
from pathlib import Path
import socket
import struct
import sys
import tempfile
import threading
import time
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'src'))
import msxpi_nitros
from msxpi_nitros import DriveWire, Session, packet, receive
from msxpi_settings import MSXPiConfig


class DriveWireTests(unittest.TestCase):
    def setUp(self):
        self.image = tempfile.TemporaryFile()
        self.image.write(b'\x00\x00\x10' + bytes(253))  # sparse 16-sector image
        self.image.flush()
        self.dw = DriveWire([self.image])
        self.client, self.server = socket.socketpair()
        self.client.settimeout(2)
        self.stop = threading.Event()
        self.failure = None
        def serve():
            try:
                self.dw.serve(self.server, self.stop)
            except EOFError:
                pass
            except Exception as exc:
                self.failure = exc
        self.thread = threading.Thread(target=serve)
        self.thread.start()

    def tearDown(self):
        self.stop.set()
        self.client.close()
        self.thread.join(3)
        self.server.close()
        self.image.close()
        self.assertFalse(self.thread.is_alive())
        if self.failure:
            raise self.failure

    def read_sector(self, sector, expected_status=0):
        self.client.sendall(b'\xd2\x00' + sector.to_bytes(3, 'big'))
        data = receive(self.client, 256)
        self.client.sendall(struct.pack('>H', sum(data)))
        self.assertEqual(receive(self.client, 1), bytes((expected_status,)))
        return data

    def test_sparse_read_and_binary_write(self):
        self.assertEqual(self.read_sector(7), bytes(256))
        data = bytes(range(256))
        request = b'\x57\x00\x00\x00\x07' + data + struct.pack('>H', sum(data))
        # Deliberate TCP fragmentation.
        for i in range(0, len(request), 13):
            self.client.sendall(request[i:i+13])
        self.assertEqual(receive(self.client, 1), b'\0')
        self.assertEqual(self.read_sector(7), data)
        self.read_sector(16, 211)

    def test_keyboard_modifier_status_and_version(self):
        self.client.sendall(b'\x5a\x01\x44\x00\x27')
        self.assertEqual(receive(self.client, 2), b'\x04\x00')

    def test_bad_checksum_does_not_write(self):
        self.client.sendall(b'\x57\0\0\0\x01' + b'A'*256 + b'\0\0')
        self.assertEqual(receive(self.client, 1), b'\xf3')
        self.assertEqual(self.read_sector(1), bytes(256))

    def test_keyboard_console_and_guest_exit(self):
        self.dw.keys.extend(b'help\r')
        self.client.sendall(b'\x43')
        self.assertEqual(receive(self.client, 2), b'\x11\x05')
        self.client.sendall(b'\x63\x00\x03')
        self.assertEqual(receive(self.client, 3), b'hel')
        for char in b'p\r':
            self.client.sendall(b'\x43')
            self.assertEqual(receive(self.client, 2), bytes((1, char)))
        self.client.sendall(b'\x43')
        self.assertEqual(receive(self.client, 2), bytes(2))
        self.client.sendall(b'\x80H\xc3\x00i\x64\x00\x02\r\n\x43')
        receive(self.client, 2)  # barrier
        self.assertEqual(bytes(self.dw.output), b'Hi\r\n')
        self.client.sendall(b'\x64\x01\x0bMSXPI-EXIT\r')
        self.thread.join(2)
        self.assertTrue(self.dw.exit_requested)


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        for name in ('boot', 'exchange'):
            (root / name).write_bytes(b'\0\0\x10' + bytes(253))
        self.config = dict(boot_disk=str(root/'boot'), exchange_disk=str(root/'exchange'),
                           xroar=[sys.executable, '-c', 'import time; time.sleep(60)'])
        self.session = Session()

    def test_runtime_config_path_comes_from_msxpi_ini(self):
        root = Path(self.tmp.name)
        runtime = root / 'nitros.json'
        runtime.write_text('{"boot_disk":"boot.dsk","exchange_disk":"exchange.dsk",'
                           '"exchange_dir":"files"}')
        ini = root / 'msxpi.ini'
        ini.write_text(f'var NITROS_CONFIG={runtime}\n')
        import msxpi_settings
        original = msxpi_settings._config
        msxpi_settings._config = MSXPiConfig.load(str(ini))
        try:
            config = msxpi_nitros.load_config()
        finally:
            msxpi_settings._config = original
        self.assertEqual(config['boot_disk'], str(root / 'boot.dsk'))
        self.assertEqual(config['exchange_dir'], str(root / 'files'))

    def tearDown(self):
        self.session.close()
        self.tmp.cleanup()

    def test_start_stop_restart(self):
        self.assertIsNone(self.session.process)
        for _ in range(3):
            self.session.start(self.config)
            process = self.session.process
            self.assertIsNone(process.poll())
            with self.assertRaisesRegex(ValueError, 'already'):
                self.session.start(self.config)
            self.assertEqual(self.session.poll()[4], 1)
            self.session.close()
            self.assertIsNotNone(process.poll())
        self.session.close()

    def test_second_server_cannot_mount_live_images(self):
        self.session.start(self.config)
        other = Session()
        try:
            with self.assertRaises(BlockingIOError):
                other.start(self.config)
            self.assertIsNone(other.process)
            self.assertIsNone(self.session.process.poll())
        finally:
            other.close()

    def test_partial_guest_request_is_interruptible(self):
        self.session.start(self.config)
        peer = socket.create_connection(self.session.listener.getsockname())
        peer.sendall(b'\x57\0')
        time.sleep(.05)
        started = time.monotonic()
        self.session.close()
        peer.close()
        self.assertLess(time.monotonic() - started, 3)

    def test_failed_launch_releases_image_locks(self):
        config = dict(self.config, xroar=['/no/such/xroar'])
        with self.assertRaises(FileNotFoundError):
            self.session.start(config)
        self.assertEqual(self.session.images, [])
        self.session.start(self.config)

    def test_lost_console_stops_child(self):
        self.session.start(self.config)
        process = self.session.process
        self.session.last_poll -= 100
        process.wait(timeout=4)
        self.assertIn('lease', self.session.error)

    def test_guest_control_stops_child(self):
        self.session.start(self.config)
        process = self.session.process
        peer = socket.create_connection(self.session.listener.getsockname())
        peer.sendall(b'\x64\x01\x0bMSXPI-EXIT\r')
        process.wait(timeout=4)
        peer.close()

    def test_emulator_failure_is_reported(self):
        self.session.start(dict(self.config, xroar=[sys.executable, '-c', 'raise SystemExit(7)']))
        deadline = time.monotonic() + 4
        while self.session.process is not None and time.monotonic() < deadline:
            time.sleep(.05)
        self.assertEqual(self.session.poll()[4], 3)

    def test_packet_is_fixed_size_and_length_delimited(self):
        response = packet(1, b'a\0b')
        self.assertEqual(len(response), 256)
        self.assertEqual(response[:8], b'NTR1\x01\x03\0\0')


if __name__ == '__main__':
    unittest.main()
