import os
import sys
import threading
import time
import unittest
from pathlib import Path
from unittest.mock import patch
from pchess_irc_fixture import Server
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
import msxpi_chat
from msxpi_chat import HEADER, handle_command


def rows(packet,width):
    slot=2+width
    return [(packet[HEADER+i*slot],packet[HEADER+i*slot+1],
             packet[HEADER+i*slot+2:HEADER+(i+1)*slot].rstrip(b'\0').decode())
            for i in range(packet[7])]

def wait(check,seconds=3):
    end=time.time()+seconds
    while time.time()<end:
        if check(): return True
        time.sleep(0.02)
    return False


class Chat(unittest.TestCase):
    def setUp(self):
        self.server=Server(('127.0.0.1',0))
        threading.Thread(target=self.server.serve_forever,daemon=True).start()
        port=self.server.server_address[1]
        self.env=patch.dict(os.environ,{'PCHESS_IRC_HOST':'127.0.0.1','PCHESS_IRC_PORT':str(port),'PCHESS_IRC_TLS':'0'})
        self.env.start()
        p=handle_command('start alice 40')
        self.assertEqual(p[:4],b'CHT1')
        self.chat=msxpi_chat._chat
        self.assertTrue(wait(lambda:self.chat.ready and self.chat.rooms[0].joined))

    def tearDown(self):
        handle_command('quit')
        self.env.stop()
        self.server.shutdown(); self.server.server_close()

    def get(self,room=0,start=0):
        packet=handle_command(f'get {room} {start}')
        self.assertEqual(len(packet),256)
        return rows(packet,40)

    def test_default_room_and_own_message(self):
        handle_command('say hello world')
        p=handle_command('get 0 0')
        self.assertEqual(p[5:6],b'M')
        texts=[r[2] for r in rows(p,40)]
        self.assertIn('Joined #msxpi',texts)
        self.assertIn('alice: hello world',[r[2] for r in self.get(0,0)]+[r[2] for r in self.get(0,5)])
        self.assertTrue(wait(lambda:self.server.transcript and self.server.transcript[-1]==('alice','#msxpi','hello world')))

    def test_incoming_wraps_and_private(self):
        self.server.clients['alice'].send(':bob!t@h PRIVMSG #msxpi :'+'word '*20)
        self.server.clients['alice'].send(':bob!t@h PRIVMSG alice :psst')
        self.assertTrue(wait(lambda:any('psst' in r[2] for r in self.chat.rooms[0].rows)))
        got=self.get(0,0)+self.get(0,5)+self.get(0,10)
        long=[r for r in got if r[0]==0]
        self.assertEqual(long[0][1],5)             # "bob: "
        self.assertTrue(all(len(r[2])<=40 for r in got))
        self.assertTrue(any(r[0]==1 and r[2]=='*bob* psst' for r in got))

    def test_pchess_traffic_hidden(self):
        self.server.clients['alice'].send(':bob!t@h PRIVMSG #msxpi :PCH1 SEEK')
        self.server.clients['alice'].send(':bob!t@h PRIVMSG #msxpi :hi')
        self.assertTrue(wait(lambda:any('bob: hi' in r[2] for r in self.get(0,0))))
        self.assertFalse(any('PCH1' in r[2] for r in self.get(0,0)))

    def test_rooms_and_users(self):
        handle_command('say /join #second')
        self.assertTrue(wait(lambda:self.chat.rooms[1].joined))
        meta=handle_command('meta 0')
        self.assertEqual(len(meta),256)
        self.assertEqual(meta[6],2)
        self.assertEqual(meta[7],1)
        self.assertEqual(meta[24+12:24+12+7],b'#second')
        handle_command('room 0')
        self.assertEqual(handle_command('get 0 99999')[21],0)
        self.server.clients['alice'].send(':bob!t@h JOIN :#msxpi')
        self.server.clients['alice'].send(':srv 353 alice = #msxpi :@carol +dave erin')
        self.assertTrue(wait(lambda:'erin' in self.chat.rooms[0].users))
        meta=handle_command('meta 0')
        names=[meta[72+i*12:72+i*12+11].rstrip(b'\0').decode() for i in range(meta[10])]
        self.assertEqual(names[:4],['@carol','+dave','alice','bob'])

    def test_msg_part_and_errors(self):
        handle_command('say /msg bob secret')
        self.assertTrue(wait(lambda:self.server.transcript and self.server.transcript[-1]==('alice','bob','secret')))
        handle_command('say /part')
        handle_command('say /bogus')
        texts=[r[2] for r in self.get(0,0)]+[r[2] for r in self.get(0,5)]+[r[2] for r in self.get(0,10)]
        self.assertTrue(any('only room' in t for t in texts))
        self.assertTrue(any('Unknown' in t for t in texts))

    def test_no_session(self):
        handle_command('quit')
        self.assertEqual(handle_command('get 0 0')[4],4)
        # tearDown quits again; reconnect not needed


if __name__=='__main__':
    unittest.main()
