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

"""Protocol equivalence for native/Python payloads; no GPIO or server startup."""
import ast
import ctypes
import importlib.util
from pathlib import Path
import unittest

SRC = Path(__file__).resolve().parents[1]/'Server/Python/src'
TREE = ast.parse((SRC/'msxpi-server.py').read_text(encoding='utf-8-sig'))
NAMES = {'SPI_BurstOut', 'SPI_ReadPayload', 'SPI_WritePayload', 'recvdata2', 'recvdata2_oneblock', 'senddata_oneblock'}
CODE = compile(ast.Module(body=[n for n in TREE.body if isinstance(n, ast.FunctionDef) and n.name in NAMES], type_ignores=[]), 'server-functions', 'exec')
CONSTANTS = {}
for node in TREE.body:
    if isinstance(node, ast.Assign) and len(node.targets)==1 and isinstance(node.targets[0], ast.Name):
        name=node.targets[0].id
        if name.startswith('RC_') or name in {'READY', 'READY_ACK', 'MAX_BLOCK_RETRIES', 'GLOBALRETRIES'}:
            CONSTANTS[name]=ast.literal_eval(node.value)


class Wire:
    def __init__(self, data):
        self.data=bytearray(data)
        self.sent=[]
        self.native_calls=0
        self.byte_calls=0

    def byte(self, output=None):
        self.byte_calls+=1
        if output is not None:
            self.sent.append(output)
            return CONSTANTS['RC_SUCCESS'], 0
        assert self.data, 'unexpected read'
        return CONSTANTS['RC_SUCCESS'], self.data.pop(0)

    def read(self, length):
        self.native_calls+=1
        assert len(self.data)>=length
        value=self.data[:length]
        del self.data[:length]
        return value

    def write(self, payload):
        self.native_calls+=1
        self.sent.extend(payload)


def context(data, native):
    wire=Wire(data)
    namespace=dict(CONSTANTS, hostType='RaspberryPi' if native else 'Linux',
                   _NATIVE_GPIO=wire if native else None, _PROFILE=False,
                   SPI_ByteTransfer=wire.byte, eth_handle_opcode=lambda _: False)
    exec(CODE, namespace)
    return namespace, wire


def checksum(payload):
    total=sum(payload)
    return ((total & 255)+((total>>8)&255))&255


class ProtocolTests(unittest.TestCase):
    def test_send_frame_and_checksum_retry_identical(self):
        for size in (0, 1, 255, 256, 257, 512, 8192):
            payload=bytes((i*73)&255 for i in range(size))
            cs=checksum(payload)
            replies=[cs^1, cs, CONSTANTS['READY'], CONSTANTS['RC_SUCCESS']]
            results=[]
            for native in (False, True):
                ns,w=context(replies,native)
                rc=ns['senddata_oneblock'](payload,8192,ns['RC_SUCCESS'],0)
                self.assertEqual(rc, ns['RC_SUCCESS'])
                self.assertFalse(w.data)
                results.append(w.sent)
                if native: self.assertEqual(w.native_calls,2)
            self.assertEqual(*results)

    def test_receive_frame_and_checksum_retry_identical(self):
        for function in ('recvdata2', 'recvdata2_oneblock'):
            payload=bytes(range(256))*2
            frame=[CONSTANTS['RC_SUCCESS'],0,2,0]+list(payload)
            incoming=[CONSTANTS['READY'],0,32]+frame+[checksum(payload)^1]+frame+[checksum(payload),CONSTANTS['READY_ACK']]
            results=[]
            for native in (False, True):
                ns,w=context(incoming,native)
                rc,data=ns[function](8192)
                self.assertEqual(rc,ns['RC_SUCCESS'])
                self.assertEqual(data,payload)
                self.assertFalse(w.data)
                results.append(w.sent)
                if native: self.assertEqual(w.native_calls,2)
            self.assertEqual(*results)

    def test_partial_native_failure_does_not_fall_back(self):
        ns,w=context([],True)
        def fail(*_): raise OSError('injected partial transfer')
        w.read=w.write=fail
        self.assertEqual(ns['SPI_ReadPayload'](512),(ns['RC_CONNERR'],None))
        self.assertEqual(ns['SPI_WritePayload'](bytes(512)),ns['RC_CONNERR'])
        self.assertEqual(w.byte_calls,0)

    def test_native_burst_and_no_unsafe_fallback(self):
        ns,w=context([],True)
        w.write_burst=w.write
        self.assertEqual(ns['SPI_BurstOut'](bytes(range(256))*3),ns['RC_SUCCESS'])
        self.assertEqual(w.native_calls,1)
        self.assertEqual(len(w.sent),768)
        def fail(*_): raise OSError('injected burst timeout')
        w.write_burst=fail
        self.assertEqual(ns['SPI_BurstOut'](b'abc'),ns['RC_CONNERR'])
        self.assertEqual(w.byte_calls,0)
        ns['_NATIVE_GPIO']=None;ns['_FAST_GPIO']=False
        self.assertEqual(ns['SPI_BurstOut'](b'abc'),ns['RC_CONNERR'])
        self.assertEqual(w.byte_calls,0)

    def test_wrapper_chunk_boundaries(self):
        spec=importlib.util.spec_from_file_location('native',SRC/'msxpi_gpio_native.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        engine=module.NativeGPIO.__new__(module.NativeGPIO)
        engine.registers=engine.masks=None
        engine.half_period_ns=500;engine.timeout_ms=1000
        engine.bytes=engine.wait_ns=engine.elapsed_ns=0
        calls=[]
        def transfer(regs,masks,tx,rx,n,half,timeout,done,wait):
            calls.append(n)
            if rx is not None:
                for i in range(n): rx[i]=i&255
            done._obj.value=n;wait._obj.value=100
            return 0
        engine.transfer=transfer
        data=engine.read(513)
        self.assertEqual(calls,[256,256,1])
        self.assertEqual(data,bytes(range(256))*2+b'\0')
        calls.clear();engine.write(data)
        self.assertEqual(calls,[256,256,1])
        self.assertEqual(engine.bytes,1026)
        engine.burst=transfer
        calls.clear();engine.write_burst(data)
        self.assertEqual(calls,[513])  # no READY gap at the 256-byte boundary
        with self.assertRaises(ValueError): engine.write_burst(bytes(65536))


if __name__=='__main__': unittest.main()
