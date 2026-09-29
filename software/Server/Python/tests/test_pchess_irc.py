import sys
from pathlib import Path
import unittest
import queue
import time
import threading
from unittest.mock import patch
from pchess_irc_fixture import Server
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'src'))
from msxpi_pchess_irc import Peer, IRC, PLAYER_TTL

class Transport(unittest.TestCase):
    def test_intentional_disconnect_is_not_network_failure(self):
        client=self.client([])
        client.closed=True
        client.reader()
        self.assertIsNone(client.error)

    def test_sasl_success_before_join(self):
        client=self.client([b':s CAP * ACK :sasl\r\nAUTHENTICATE :+\r\n:s 903 requested :OK\r\n:s 001 requested :Welcome\r\n'])
        client.account='testaccount'
        client.password='testpass#='
        client.auth_phase='cap'
        client.reader()
        self.assertTrue(client.authenticated)
        self.assertEqual(client.sent[0],'AUTHENTICATE PLAIN')
        self.assertEqual(client.sent[-2:],['CAP END','JOIN #msxpi'])
        self.assertEqual(client.password,'')

    def test_sasl_failure_does_not_join(self):
        client=self.client([b':s 904 requested :bad password\r\n'])
        client.account='testaccount'
        client.password='secret'
        client.auth_phase='result'
        client.reader()
        self.assertEqual(client.error,'Lobby login failed 904')
        self.assertEqual(client.sent,[])
        self.assertEqual(client.password,'')

    def test_credentials_require_tls(self):
        with patch.dict('os.environ',PCHESS_IRC_TLS='0'):
            with self.assertRaisesRegex(ValueError,'requires TLS'):
                IRC({'IRCACCOUNT':'test','IRCPASSWORD':'secret'})

    def test_two_socket_clients_private_game(self):
        server=Server(('127.0.0.1',0))
        threading.Thread(target=server.serve_forever,daemon=True).start()
        clients=[]
        def wait_for(predicate):
            deadline=time.monotonic()+3
            while not predicate():
                for client in clients: client.poll()
                if time.monotonic()>deadline: self.fail('IRC fixture timed out')
                time.sleep(.01)
        try:
            for nick in ('Alice','Bob'):
                with patch.dict('os.environ',PCHESS_IRC_HOST='127.0.0.1',
                    PCHESS_IRC_PORT=str(server.server_address[1]),PCHESS_IRC_TLS='0',
                    PCHESS_IRC_NICK=nick,PCHESS_IRC_TRACE='0'):
                    clients.append(IRC())
            a,b=clients
            wait_for(lambda: a.ready and b.ready)
            a.peer.seek()
            wait_for(lambda: 'Alice' in b.peer.players)
            a.peer.offer('Bob')
            wait_for(lambda: b.peer.invite is not None)
            b.peer.accept()
            wait_for(lambda: a.peer.phase==b.peer.phase=='playing')
            a.peer.move('e4')
            wait_for(lambda: len(b.peer.history)==1 and not a.peer.pending)
            b.peer.move('e5')
            wait_for(lambda: len(a.peer.history)==2 and not b.peer.pending)
            self.assertEqual(a.peer.board.fen(),b.peer.board.fen())
            self.assertTrue(all(text=='PCH1 SEEK' for _,target,text in server.transcript if target=='#msxpi'))
        finally:
            for client in clients: client.close()
            server.shutdown()
            server.server_close()

    def client(self, chunks):
        class Socket:
            def recv(self, size): return chunks.pop(0) if chunks else b''
            def close(self): pass
        client=IRC.__new__(IRC)
        client.sock=Socket()
        client.nick='requested'
        client.account=''
        client.password=''
        client.authenticated=False
        client.auth_phase='none'
        client.peer=Peer(client.nick,client.message)
        client.ready=False
        client.error=None
        client.messages=queue.Queue(256)
        client.started=time.monotonic()
        client.sent=[]
        client.line=client.sent.append
        return client

    def test_fragmented_registration_ping_and_private_message(self):
        client=self.client([b':server 001 actual :Welcome\r\nPI',
            b'NG :token\r\n:actual!u@h JOIN :#msxpi\r\n'
            b'@time=x :other!u@h PRIVMSG actual :PCH1 SEEK\r\n'])
        client.reader()
        self.assertEqual(client.nick,'actual')
        self.assertEqual(client.peer.nick,'actual')
        self.assertTrue(client.ready)
        self.assertEqual(client.sent,['JOIN #msxpi','PONG :token'])
        self.assertEqual(client.messages.get_nowait(),('other','actual','PCH1 SEEK'))
        self.assertEqual(client.error,'Lobby disconnected')

    def test_send_before_join_is_rejected(self):
        client=self.client([])
        with self.assertRaisesRegex(ValueError,'not ready'):
            client.message('#msxpi','PCH1 SEEK')
        self.assertEqual(client.sent,[])

    def test_join_rejection_is_reported(self):
        client=self.client([b':server 474 nick #msxpi :Banned\r\n'])
        client.reader()
        self.assertEqual(client.error,'#msxpi: Banned')
        self.assertFalse(client.ready)

    def test_no_such_nick_stays_in_lobby(self):
        client=self.client([b':server 401 nick bob :No such nick/channel\r\n'])
        client.peer.peer='bob'; client.peer.match='0'*16; client.peer.phase='offered'
        client.reader()
        self.assertEqual(client.error,'Lobby disconnected')
        self.assertEqual(client.peer.status,'bob: No such nick')
        self.assertEqual(client.peer.phase,'lobby')
        self.assertIsNone(client.peer.peer)

    def test_account_requirement_fits_msx_status(self):
        client=self.client([b':server 477 nick peer :You need to be identified to a registered account to message this user\r\n'])
        client.reader()
        self.assertEqual(client.error,'Lobby account login required (477)')
        self.assertLessEqual(len(client.error),47)

class Protocol(unittest.TestCase):
    def setUp(self):
        self.messages=[]
        self.a=Peer('Alice',lambda target,text:self.messages.append(('Alice',target,text)))
        self.b=Peer('Bob',lambda target,text:self.messages.append(('Bob',target,text)))
    def deliver(self):
        while self.messages:
            sender,target,text=self.messages.pop(0)
            (self.a if target=='Alice' else self.b).receive(sender,target,text)
    def start(self):
        self.a.offer('Bob'); self.deliver(); self.b.accept(); self.deliver()
    def test_channel_is_only_discovery(self):
        self.a.seek()
        self.assertEqual(self.messages,[('Alice','#msxpi','PCH1 SEEK')])
        self.deliver()
        self.assertIn('Alice',self.b.players)
        with self.assertRaises(ValueError): self.a.seek()
        self.start()
        self.a.move('e4')
        self.assertTrue(all(target!='#msxpi' for _,target,_ in self.messages))
    def test_draw_offer_accept_and_decline(self):
        self.start()
        with self.assertRaises(ValueError): self.b.draw()   # not Bob's move
        self.a.draw(); self.deliver()
        self.assertEqual(self.b.snapshot()['status'],'OPPONENT OFFERS DRAW - ESC MENU')
        self.a.move('e4'); self.deliver()                   # own move keeps it
        self.b.move('e5'); self.deliver()                   # Bob moves: declined
        self.assertIsNone(self.a.draw_offer); self.assertIsNone(self.b.draw_offer)
        self.a.draw(); self.deliver(); self.b.draw(); self.deliver()
        for peer in (self.a,self.b):
            state=peer.snapshot()
            self.assertEqual((state['status'],state['over']),('DRAW AGREED',True))
        with self.assertRaises(ValueError): self.a.move('d4')
    def test_resign(self):
        self.start(); self.a.move('e4'); self.deliver()
        self.b.resign(); self.deliver()
        for peer in (self.a,self.b):
            self.assertEqual(peer.snapshot()['status'],'BLACK RESIGNED - WHITE WINS')
            self.assertTrue(peer.snapshot()['over'])
        with self.assertRaises(ValueError): self.a.resign()
    def test_moves_ack_duplicate(self):
        self.start(); self.a.move('e4')
        frame=self.messages[0]
        self.deliver()
        self.assertIsNone(self.a.pending)
        self.b.receive(*frame); self.deliver()
        self.assertEqual(len(self.b.board.move_stack),1)
        self.b.move('e5'); self.deliver()
        self.assertEqual(self.a.board.fen(),self.b.board.fen())
    def test_forged_and_public_moves_ignored(self):
        self.start(); self.a.move('e4')
        sender,target,text=self.messages[0]
        self.b.receive('Mallory',target,text)
        self.b.receive(sender,'#msxpi',text)
        self.assertEqual(len(self.b.board.move_stack),0)
        self.deliver()
    def test_no_play_before_accept(self):
        self.a.offer('Bob'); self.deliver()
        with self.assertRaises(ValueError): self.a.move('e4')
        self.assertEqual(self.b.phase,'lobby')
    def test_bad_hash_does_not_apply(self):
        self.start(); self.a.move('e4')
        sender,target,text=self.messages.pop()
        bad=text.rsplit(' ',1)[0]+' 0000000000000000'
        self.b.receive(sender,target,bad)
        self.assertEqual(len(self.b.board.move_stack),0)
        self.assertEqual(self.b.phase,'error')
    def test_players_lists_recent_seekers_and_offers(self):
        self.a.seek(); self.deliver()
        self.b.receive('Carol','#msxpi','PCH1 SEEK')
        self.assertEqual(self.b.recent_players(),['Carol','Alice'])
        self.b.players['Alice']-=PLAYER_TTL
        self.assertEqual(self.b.recent_players(),['Carol'])
        self.b.no_such_nick('carol')
        self.assertEqual(self.b.recent_players(),[])
        self.a.offer('Bob'); self.deliver()
        self.assertEqual(self.b.recent_players(),['Alice'])
    def test_status_names_colours(self):
        self.start()
        self.assertEqual(self.a.status,'YOU ARE WHITE - YOUR MOVE')
        self.assertEqual(self.b.status,'YOU ARE BLACK - Alice MOVES')
        self.assertTrue(self.a.snapshot()['matched'])
        self.assertEqual(self.b.snapshot()['opponent'],'Alice')
        self.assertEqual(self.b.snapshot()['side'],1)
        self.a.move('e4'); self.deliver()
        self.assertEqual(self.a.status,'YOU ARE WHITE - Bob MOVES')
        self.assertEqual(self.b.status,'YOU ARE BLACK - YOUR MOVE')
    def test_missing_ack_retries_then_stops(self):
        self.start(); self.a.move('e4')
        for i in range(4):
            message,_,retries=self.a.pending
            self.a.pending=(message,0,retries)
            self.a.tick()
        self.assertEqual(self.a.phase,'error')
        self.assertEqual(len(self.a.board.move_stack),1)

if __name__=='__main__': unittest.main()
