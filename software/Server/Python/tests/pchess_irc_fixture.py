"""Minimal local IRC fixture for integration tests; never connects publicly."""
import socketserver
import threading
import time

class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address=True
    daemon_threads=True
    def __init__(self,address):
        super().__init__(address,Handler)
        self.clients={}
        self.channels={}
        self.lock=threading.RLock()
        self.transcript=[]
        self.ghost={}          # nick -> time until a dead link still holds it
        self.ghost_delay=0

class Handler(socketserver.StreamRequestHandler):
    def send(self,line):
        self.wfile.write((line+'\r\n').encode()); self.wfile.flush()
    def handle(self):
        nick=None
        try:
            for raw in self.rfile:
                line=raw.decode().rstrip('\r\n')
                with self.server.lock:
                    if line.startswith('NICK '):
                        wanted=line[5:]
                        if wanted in self.server.clients or time.monotonic()<self.server.ghost.get(wanted,0):
                            self.send(f':test 433 * {wanted} :Nickname is already in use')
                            continue
                        nick=wanted; self.server.clients[nick]=self
                    elif line.startswith('USER ') and nick:
                        self.send(f':test 001 {nick} :Welcome')
                    elif line.startswith('JOIN #') and nick:
                        channel=line[5:].lower()
                        self.server.channels.setdefault(channel,set()).add(nick)
                        self.send(f':{nick}!test@localhost JOIN :{channel}')
                        self.send(f':test 353 {nick} = {channel} :'+' '.join(sorted(self.server.channels[channel])))
                        self.send(f':test 366 {nick} {channel} :End of /NAMES list.')
                    elif line.startswith('PRIVMSG ') and nick:
                        target,text=line[8:].split(' :',1)
                        self.server.transcript.append((nick,target,text))
                        targets=(list(self.server.channels.get(target.lower(),()))
                                 if target.startswith('#') else [target])
                        for recipient in targets:
                            if recipient!=nick and recipient in self.server.clients:
                                self.server.clients[recipient].send(f':{nick}!test@localhost PRIVMSG {target} :{text}')
                            elif recipient!=nick and not target.startswith('#'):
                                self.send(f':test 401 {nick} {recipient} :No such nick/channel')
        except (ConnectionError,OSError):
            pass
        finally:
            with self.server.lock:
                if nick and self.server.clients.get(nick) is self and self.server.ghost_delay:
                    self.server.ghost[nick]=time.monotonic()+self.server.ghost_delay
                if self.server.clients.get(nick) is self: self.server.clients.pop(nick,None)
                for members in self.server.channels.values(): members.discard(nick)
