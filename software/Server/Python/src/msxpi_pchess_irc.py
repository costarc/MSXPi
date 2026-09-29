"""PCH1 IRC protocol: discovery in #msxpi, all game traffic private."""
import hashlib
import base64
import os
import queue
import re
import secrets
import socket
import ssl
import threading
import time
import chess

def fold(nick):
    return nick.lower().translate(str.maketrans('[]\\^','{}|~'))

def digest(board):
    return hashlib.sha256(board.fen().encode()).hexdigest()[:16]

class Peer:
    def __init__(self,nick,send):
        self.nick=nick
        self.send=send
        self.board=chess.Board()
        self.peer=None
        self.match=None
        self.side=True
        self.phase='lobby'
        self.status='LOBBY'
        self.invite=None
        self.pending=None
        self.history=[]
        self.last_move=None
        self.players={}
        self.last_seek=-1000

    def seek(self):
        if self.phase!='lobby': raise ValueError('Already in a match')
        if time.monotonic()-self.last_seek<60: raise ValueError('Wait before announcing again')
        self.send('#msxpi','PCH1 SEEK')
        self.last_seek=time.monotonic()
        self.status='SEEK SENT'

    def offer(self,nick):
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]{0,15}',nick): raise ValueError('Invalid nickname')
        if self.phase!='lobby' or fold(nick)==fold(self.nick): raise ValueError('Cannot challenge now')
        self.peer=nick
        self.match=secrets.token_hex(8)
        self.phase='offered'
        self.send(nick,f'PCH1 OFFER {self.match}')
        self.status='INVITE SENT'

    def accept(self):
        if self.phase!='lobby' or not self.invite: raise ValueError('No invitation')
        self.peer,self.match=self.invite
        self.invite=None
        self.side=False
        self.phase='accepted'
        self.send(self.peer,f'PCH1 ACCEPT {self.match}')
        self.status='WAIT READY'

    def no_such_nick(self,nick):
        # An invite (or acceptance) to a missing player is abandoned; a game
        # in progress is left to the normal move retransmit and timeout.
        if self.peer and fold(nick)==fold(self.peer) and self.phase in ('offered','accepted'):
            self.peer=None; self.match=None; self.phase='lobby'
        self.status=(nick+': No such nick')[:47]

    def receive(self,sender,target,text):
        fields=text.split()
        if len(fields)<2 or fields[0]!='PCH1' or fold(sender)==fold(self.nick): return
        op=fields[1]
        if fold(target)==fold('#msxpi'):
            if fields==['PCH1','SEEK'] and self.phase=='lobby':
                if len(self.players)>=64: self.players.pop(next(iter(self.players)))
                self.players[sender]=time.monotonic()
                self.status='PLAYER '+sender
            return
        if fold(target)!=fold(self.nick): return
        if op=='OFFER' and len(fields)==3 and re.fullmatch('[0-9a-f]{16}',fields[2]):
            if self.phase=='lobby':
                self.invite=(sender,fields[2])
                self.status='INVITE '+sender+' PRESS 7'
            return
        if not self.peer or fold(sender)!=fold(self.peer) or len(fields)<3 or fields[2]!=self.match: return
        if op=='ACCEPT' and len(fields)==3 and self.phase in ('offered','playing'):
            if self.phase=='offered': self.side=True; self.phase='playing'; self.status='WHITE TURN'
            self.send(self.peer,f'PCH1 READY {self.match}')
        elif op=='READY' and len(fields)==3 and self.phase=='accepted':
            self.phase='playing'; self.status='WHITE TURN'
        elif op=='MOVE' and len(fields)==7 and self.phase=='playing':
            if text==self.last_move:
                self.send(self.peer,f'PCH1 ACK {self.match} {fields[3]} {fields[6]}')
                return
            if self.pending or self.board.turn==self.side: return
            if fields[3]!=str(len(self.board.move_stack)+1) or fields[5]!=digest(self.board):
                self.status='OUT OF SYNC'; self.phase='error'; return
            try: move=self.board.parse_uci(fields[4])
            except ValueError: return
            san=self.board.san(move)
            self.board.push(move)
            if digest(self.board)!=fields[6]:
                self.board.pop(); self.status='BAD POSITION'; self.phase='error'; return
            self.history.append(san)
            self.last_move=text
            self.send(self.peer,f'PCH1 ACK {self.match} {fields[3]} {fields[6]}')
            self.status='WHITE TURN' if self.board.turn else 'BLACK TURN'
        elif op=='ACK' and len(fields)==5 and self.pending:
            if fields[3]==str(len(self.board.move_stack)) and fields[4]==digest(self.board):
                self.pending=None
                self.status='WHITE TURN' if self.board.turn else 'BLACK TURN'

    def move(self,notation):
        if self.phase!='playing' or self.pending: raise ValueError('Waiting for peer')
        if self.board.turn!=self.side: raise ValueError('Opponent turn')
        if self.board.is_game_over(claim_draw=True): raise ValueError('Game over')
        try: move=self.board.parse_uci(notation.lower().replace('-',''))
        except ValueError: move=self.board.parse_san(notation)
        before=digest(self.board)
        san=self.board.san(move)
        self.board.push(move)
        message=f'PCH1 MOVE {self.match} {len(self.board.move_stack)} {move.uci()} {before} {digest(self.board)}'
        try: self.send(self.peer,message)
        except Exception:
            self.board.pop(); raise
        self.history.append(san)
        self.pending=(message,time.monotonic(),0)
        self.status='WAIT ACK'

    def tick(self):
        if self.pending:
            message,sent,retries=self.pending
            if time.monotonic()-sent>=5:
                if retries>=3:
                    self.phase='error'; self.status='PEER TIMEOUT'; self.pending=None
                else:
                    self.send(self.peer,message)
                    self.pending=(message,time.monotonic(),retries+1)

    def snapshot(self):
        board=self.board
        status=self.status
        outcome=board.outcome(claim_draw=True)
        if outcome:
            status='DRAW' if outcome.winner is None else 'WHITE WINS' if outcome.winner else 'BLACK WINS'
        elif board.is_check() and self.phase=='playing' and not self.pending:
            status='WHITE CHECK' if board.turn else 'BLACK CHECK'
        return dict(board=''.join(board.piece_at(chess.square(x,7-y)).symbol()
            if board.piece_at(chess.square(x,7-y)) else '.' for y in range(8) for x in range(8)),
            turn=int(board.turn),side=int(not self.side),over=bool(outcome),
            status=status[:47],history=self.history[-12:],ply=len(board.move_stack))


def tls_context():
    """System CAs plus certifi's bundle when installed.

    Some system stores (the Microsoft Store Python on Windows, OpenSSL 3.0)
    build an expired path for Let's Encrypt's 2026 chain; certifi's bundle
    lets verification find the valid one. Verification stays on."""
    context=ssl.create_default_context()
    try:
        import certifi
        context.load_verify_locations(certifi.where())
    except (ImportError,OSError):
        pass
    return context


class IRC:
    def __init__(self,config=None):
        config=config or {}
        self.nick=os.environ.get('PCHESS_IRC_NICK') or config.get('IRCNICK') or 'pch'+secrets.token_hex(2)
        if not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]{0,15}',self.nick): raise ValueError('Invalid lobby nickname (IRCNICK)')
        host=os.environ.get('PCHESS_IRC_HOST') or config.get('IRCADDR') or 'irc.libera.chat'
        self.account=config.get('IRCACCOUNT','')
        self.password=config.get('IRCPASSWORD','')
        if bool(self.account)!=bool(self.password):
            raise ValueError('Set both IRCACCOUNT and IRCPASSWORD')
        if any(c in self.account+self.password for c in '\x00\r\n'):
            raise ValueError('Invalid lobby account (IRCACCOUNT)')
        self.authenticated=False
        self.auth_phase='cap' if self.account else 'none'
        port=int(os.environ.get('PCHESS_IRC_PORT') or config.get('PCHESSIRCPORT') or '6697')
        tls_value=os.environ.get('PCHESS_IRC_TLS') or config.get('IRCTLS') or ('0' if port==6667 else '1')
        tls=tls_value.lower() in ('1','true','yes','on')
        if self.account and not tls:
            raise ValueError('Lobby login requires TLS')
        sock=socket.create_connection((host,port),timeout=5)
        try:
            if tls:
                sock=tls_context().wrap_socket(sock,server_hostname=host)
        except ssl.SSLCertVerificationError as exc:
            sock.close()
            print('PCHESS IRC TLS '+str(exc),flush=True)
            raise ValueError('Lobby certificate error') from None
        except Exception:
            sock.close(); raise
        self.sock=sock
        self.lock=threading.Lock()
        self.messages=queue.Queue(256)
        self.error=None
        self.closed=False
        self.ready=False
        self.started=time.monotonic()
        self.peer=Peer(self.nick,self.message)
        self.peer.status='ACCESSING LOBBY'
        if self.account: self.line('CAP REQ :sasl')
        self.line(f'NICK {self.nick}')
        self.line(f'USER {self.nick} 0 * :MSXPi PChess')
        threading.Thread(target=self.reader,daemon=True).start()

    def line(self,line):
        if '\r' in line or '\n' in line or len(line)>450: raise ValueError('Invalid lobby message')
        with self.lock: self.sock.sendall((line+'\r\n').encode('ascii'))

    def message(self,target,text):
        if not self.ready: raise ValueError('Lobby not ready; wait')
        self.line(f'PRIVMSG {target} :{text}')
        if os.environ.get('PCHESS_IRC_TRACE')=='1':
            print(f'PCHESS IRC TX {target} :{text}',flush=True)

    def reader(self):
        buffer=b''
        try:
            while True:
                try: data=self.sock.recv(4096)
                except socket.timeout: continue
                if not data: raise ConnectionError('Lobby disconnected')
                buffer+=data
                if len(buffer)>16384: raise ValueError('Lobby message too large')
                while b'\n' in buffer:
                    raw,buffer=buffer.split(b'\n',1)
                    line=raw.decode('utf-8','replace').rstrip('\r')
                    if line.startswith('@'): line=line.split(' ',1)[1]
                    if line.startswith('PING '): self.line('PONG '+line[5:]); continue
                    parts=line.split(' ',3)
                    if self.authenticate(line,parts): continue
                    if line.startswith('ERROR '): raise ConnectionError(line[:150])
                    if len(parts)>1 and parts[1]=='001':
                        if self.account and not self.authenticated:
                            raise ValueError('Lobby login not confirmed')
                        self.nick=parts[2]
                        self.peer.nick=self.nick
                        self.peer.status='JOINING LOBBY'
                        self.line('JOIN #msxpi')
                    if len(parts)>2 and parts[1]=='JOIN' and fold(parts[0][1:].split('!',1)[0])==fold(self.nick) and fold(parts[2].lstrip(':'))==fold('#msxpi'):
                        self.ready=True
                        self.peer.status='LOBBY '+self.nick
                    if len(parts)>3 and parts[1]=='401':
                        # Unknown nickname: report it but stay in the lobby.
                        self.peer.no_such_nick(parts[3].partition(' :')[0].strip())
                        continue
                    if len(parts)>1 and parts[1] in ('403','404','432','464','465','471','473','474','475','477','489'):
                        if parts[1]=='477':
                            raise ValueError('Lobby account login required (477)')
                        # ":srv 401 me bob :No such nick/channel" -> "bob: No such nick/channel"
                        params,_,text=(parts[3] if len(parts)>3 else '').partition(' :')
                        subject=params.strip()
                        raise ValueError(((subject+': ' if subject else '')+(text or 'Lobby error '+parts[1]))[:140])
                    if len(parts)>1 and parts[1]=='433': raise ValueError('Lobby nickname in use')
                    if len(parts)==4 and parts[1]=='PRIVMSG' and parts[3].startswith(':PCH1 '):
                        item=(parts[0][1:].split('!',1)[0],parts[2],parts[3][1:])
                        if os.environ.get('PCHESS_IRC_TRACE')=='1':
                            print('PCHESS IRC RX '+' '.join(item),flush=True)
                        try: self.messages.put_nowait(item)
                        except queue.Full: pass
        except Exception as exc:
            self.error=None if getattr(self,'closed',False) else str(exc)
            if self.error and os.environ.get('PCHESS_IRC_TRACE')=='1':
                print('PCHESS IRC ERROR '+self.error,flush=True)
        finally:
            self.password=''
            self.sock.close()

    def authenticate(self,line,parts):
        """SASL PLAIN over verified TLS; never send credentials to chat/logs."""
        if not self.account: return False
        if len(parts)>3 and parts[1]=='CAP':
            command=parts[3].split(' ',1)[0]
            if command=='NAK': raise ValueError('Lobby server does not support login')
            if command=='ACK' and self.auth_phase=='cap':
                caps=parts[3].split(':',1)[-1].split()
                if not any(c.split('=',1)[0]=='sasl' for c in caps):
                    raise ValueError('Lobby login not acknowledged')
                self.auth_phase='challenge'
                self.peer.status='LOBBY LOGIN'
                self.line('AUTHENTICATE PLAIN')
            return True
        auth_parts=line.split(' ')
        if auth_parts[0].startswith(':'): auth_parts=auth_parts[1:]
        challenge=len(auth_parts)==2 and auth_parts[0]=='AUTHENTICATE' and auth_parts[1].lstrip(':')=='+'
        if challenge and self.auth_phase=='challenge':
            payload=base64.b64encode(('\0'+self.account+'\0'+self.password).encode('utf-8')).decode('ascii')
            self.password=''
            for pos in range(0,len(payload),400):
                self.line('AUTHENTICATE '+payload[pos:pos+400])
            if len(payload)%400==0: self.line('AUTHENTICATE +')
            self.auth_phase='result'
            return True
        if len(parts)>1 and parts[1]=='903' and self.auth_phase=='result':
            self.authenticated=True
            self.auth_phase='done'
            self.line('CAP END')
            return True
        if len(parts)>1 and parts[1] in ('902','904','905','906','907','908'):
            raise ValueError('Lobby login failed '+parts[1])
        return False

    def poll(self):
        if self.error: raise ValueError(self.error)
        if not self.ready and time.monotonic()-self.started>60:
            self.close()
            raise ValueError('Lobby connection timed out')
        while not self.messages.empty(): self.peer.receive(*self.messages.get_nowait())
        self.peer.tick()
        return self.peer.snapshot()

    def close(self):
        self.closed=True
        try: self.sock.shutdown(socket.SHUT_RDWR)
        except OSError: pass
        self.sock.close()
