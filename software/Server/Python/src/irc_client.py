import socket
import ssl
import threading
import time
from collections import deque
from typing import Deque, Dict, List, Optional, Set, Tuple

# Assuming Message is defined elsewhere in your project:
# from your_module import Message


class IRCClient:
    """
    Simple threaded IRC client with:
      - connect / disconnect
      - join / part / say
      - tracking of joined channels, user lists, and unread messages
      - basic numeric/error handling
      - thread-safe access to shared state
    """

    def __init__(self) -> None:
        self._sock: Optional[socket.socket] = None
        self._reader: Optional[threading.Thread] = None
        self._running: bool = False
        self._lock = threading.Lock()

        self._msg_id: int = 0
        self.unread: Dict[str, Deque["Message"]] = {}   # channel -> deque[Message]
        self.userlist: Dict[str, List[str]] = {}        # channel -> [nicks]
        self.joined: Set[str] = set()                   # set of channels we are in

        self.server: str = ""
        self.port: int = 6667
        self.nick: str = "msx"
        self.last_error: str = ""
        self.state: str = "DISCONNECTED"  # CONNECTING, CONNECTED, DISCONNECTED

    # -------------------------------------------------------------------------
    # Low-level socket send
    # -------------------------------------------------------------------------
    def _send_line(self, line: str) -> None:
        """Send a raw IRC line (without CRLF) to the server."""
        if not self._sock:
            return
        data = (line + "\r\n").encode("utf-8", errors="replace")
        try:
            self._sock.sendall(data)
        except Exception as e:
            self.last_error = f"send_error: {e}"
            self._stop_with_error()

    # -------------------------------------------------------------------------
    # Public API: connection management
    # -------------------------------------------------------------------------
    def connect(
        self,
        server: str,
        port: int = 6667,
        nick: str = "msx",
        use_ssl: bool = False,
        timeout: float = 10.0,
    ) -> Tuple[bool, str]:
        """
        Connect to an IRC server and start the reader thread.
        Returns (ok, message).
        """
        with self._lock:
            if self._running:
                return False, "already_running"

            self.server = server
            self.port = port
            self.nick = nick
            self.last_error = ""
            self.state = "CONNECTING"

            try:
                s = socket.create_connection((server, port), timeout=timeout)
                if use_ssl:
                    ctx = ssl.create_default_context()
                    s = ctx.wrap_socket(s, server_hostname=server)
                self._sock = s
            except Exception as e:
                self._sock = None
                self.state = "DISCONNECTED"
                self.last_error = f"connect_error: {e}"
                return False, self.last_error

            # send NICK and USER
            try:
                self._send_line(f"NICK {nick}")
                self._send_line(f"USER {nick} 0 * :{nick}")
            except Exception as e:
                self.last_error = f"register_error: {e}"
                self._stop_with_error()
                return False, self.last_error

            self._running = True
            self._reader = threading.Thread(target=self._reader_loop, daemon=True)
            self._reader.start()
            self.state = "CONNECTED"
            return True, "ok"

    def disconnect(self, reason: str = "msx_quit") -> Tuple[bool, str]:
        """
        Gracefully disconnect from the server by sending QUIT and closing the socket.
        Returns (ok, message).
        """
        with self._lock:
            if not self._running:
                return False, "not_running"

            try:
                self._send_line(f"QUIT :{reason}")
            except Exception:
                pass

            # Mark as not running; reader loop will exit soon
            self._running = False

            # Close socket here as well to unblock recv()
            try:
                if self._sock:
                    self._sock.close()
            except Exception:
                pass

            self._sock = None
            self.state = "DISCONNECTED"

        return True, "disconnected"

    def _stop_with_error(self) -> None:
        """
        Internal: stop the client due to an error.
        Ensures socket is closed and state is updated.
        """
        with self._lock:
            self._running = False
            try:
                if self._sock:
                    self._sock.close()
            except Exception:
                pass
            self._sock = None
            self.state = "DISCONNECTED"

    # -------------------------------------------------------------------------
    # Public API: IRC commands
    # -------------------------------------------------------------------------
    def join(self, channel: str) -> Tuple[bool, str]:
        """
        Request to join a channel.
        The actual confirmation is handled via JOIN / 353 in _handle_line().
        """
        with self._lock:
            if not self._running or not self._sock:
                return False, "not_connected"
            try:
                self._send_line(f"JOIN {channel}")
                return True, "sent"
            except Exception as e:
                self.last_error = f"join_error: {e}"
                return False, self.last_error

    def part(self, channel: str, reason: str = "") -> Tuple[bool, str]:
        """
        Request to part a channel.
        """
        with self._lock:
            if not self._running or not self._sock:
                return False, "not_connected"
            try:
                line = f"PART {channel}"
                if reason:
                    line += f" :{reason}"
                self._send_line(line)
                return True, "sent"
            except Exception as e:
                self.last_error = f"part_error: {e}"
                return False, self.last_error

    def say(self, target: str, text: str) -> Tuple[bool, str]:
        """
        Send a PRIVMSG to a channel or user.
        """
        with self._lock:
            if not self._running or not self._sock:
                return False, "not_connected"
            try:
                self._send_line(f"PRIVMSG {target} :{text}")
                return True, "sent"
            except Exception as e:
                self.last_error = f"say_error: {e}"
                return False, self.last_error

    # -------------------------------------------------------------------------
    # Public API: state queries and helpers
    # -------------------------------------------------------------------------
    def is_connected(self) -> bool:
        """Return True if the client is currently connected and running."""
        with self._lock:
            return self._running and self._sock is not None and self.state == "CONNECTED"

    def list_channels(self) -> List[str]:
        """Return a sorted list of channels we are currently joined to."""
        with self._lock:
            return sorted(self.joined)

    def list_users(self, channel: str) -> List[str]:
        """Return a sorted list of users in the given channel."""
        with self._lock:
            return sorted(self.userlist.get(channel, []))

    def read_all_unread(self, channel: str) -> List["Message"]:
        with self._lock:
            dq = self.unread.get(channel)
            if not dq:
                return []  # DO NOT CLEAR ANYTHING
    
            msgs = list(dq)
            print(f"read_all_unread: msgs = {msgs}")
            dq.clear()     # ONLY CLEAR WHEN WE HAVE MESSAGES
            return msgs

    def channels_with_unread(self) -> List[str]:
        """
        Return a list of channels that currently have unread messages.
        """
        with self._lock:
            return [ch for ch, dq in self.unread.items() if dq]

    def clear_unread(self, channel: str) -> None:
        """
        Clear unread messages for a specific channel.
        """
        with self._lock:
            dq = self.unread.get(channel)
            if dq:
                dq.clear()

    # -------------------------------------------------------------------------
    # Reader loop and line handling
    # -------------------------------------------------------------------------
    def _reader_loop(self) -> None:
        """
        Background thread: read lines from server and handle simple IRC events.
        """
        buffer = b""
        try:
            while True:
                with self._lock:
                    if not self._running or not self._sock:
                        break
                    sock = self._sock

                try:
                    data = sock.recv(4096)
                    if not data:
                        # connection closed
                        self.last_error = "remote_closed"
                        break
                    buffer += data
                    while b"\n" in buffer:
                        line, buffer = buffer.split(b"\n", 1)
                        try:
                            line_str = line.decode("utf-8", errors="ignore").rstrip("\r")
                            self._handle_line(line_str)
                        except Exception:
                            # ignore malformed lines
                            pass
                except socket.timeout:
                    continue
                except Exception as e:
                    self.last_error = f"recv_error: {e}"
                    break
        finally:
            self._stop_with_error()

    def _handle_line(self, line: str) -> None:
        """
        Handle a single raw IRC line.
        """
        if not line:
            return

        # Debug: log raw IRC input
        try:
            print(f"IRC RECV: {line}")
        except Exception:
            pass

        parts = line.split()
        if not parts:
            return

        # Handle PING
        if parts[0].upper() == "PING":
            token = parts[1] if len(parts) > 1 else ""
            self._send_line(f"PONG {token}")
            return

        # ------------------------------------------------------------
        # Correct RFC1459-style parsing
        # ------------------------------------------------------------
        prefix = ""
        rest = line
        
        # Extract prefix if present
        if line.startswith(":"):
            try:
                prefix, rest = line[1:].split(" ", 1)
            except ValueError:
                return
        
        # Split command and parameters, preserving trailing text
        if " :" in rest:
            before, trailing = rest.split(" :", 1)
            parts = before.split()
            parts.append(":" + trailing)  # trailing param stays intact
        else:
            parts = rest.split()
        
        if not parts:
            return
        
        cmd = parts[0]
        params = parts[1:]

        cmd_upper = cmd.upper()
        print(f"irc_client: handling command {cmd_upper} with params {params}")
        # ---------------------------------------------------------------------
        # PRIVMSG
        # ---------------------------------------------------------------------
        if cmd_upper == "PRIVMSG" and params:
            target = params[0]
        
            # Extract trailing text properly
            if params[-1].startswith(":"):
                text = " ".join(params[1:])[1:]  # remove leading :
            else:
                text = " ".join(params[1:])
        
            nick = prefix.split("!")[0] if "!" in prefix else prefix
        
            print(f"irc_client: received PRIVMSG -> target={target} and text = {text})"
            with self._lock:
                self._msg_id += 1
                msg = Message(self._msg_id, time.time(), target, nick, text)
                print(f"Inside self lock msg = {msg}")
                self.unread.setdefault(target, deque()).append(msg)
                print(
                    f"irc_client: stored PRIVMSG -> id={msg.id} "
                    f"target={target!r} nick={nick!r} text={text!r} "
                    f"unread_for_target={len(self.unread[target])}"
                )
            print("irc_client: finished handling PRIVMSG")
            return

        # ---------------------------------------------------------------------
        # JOIN
        # ---------------------------------------------------------------------
        if cmd_upper == "JOIN":
            nick = prefix.split("!")[0] if "!" in prefix else prefix
            channel = params[0] if params else ""
            if channel.startswith(":"):
                channel = channel[1:]
            with self._lock:
                self.userlist.setdefault(channel, [])
                if nick not in self.userlist[channel]:
                    self.userlist[channel].append(nick)
                if nick == self.nick:
                    self.joined.add(channel)
                    self.unread.setdefault(channel, deque())
            return

        # ---------------------------------------------------------------------
        # PART
        # ---------------------------------------------------------------------
        if cmd_upper == "PART" and params:
            nick = prefix.split("!")[0] if "!" in prefix else prefix
            channel = params[0]
            with self._lock:
                if channel in self.userlist and nick in self.userlist[channel]:
                    try:
                        self.userlist[channel].remove(nick)
                    except ValueError:
                        pass
                if nick == self.nick and channel in self.joined:
                    self.joined.discard(channel)
            return

        # ---------------------------------------------------------------------
        # 353 (NAMES reply): :server 353 nick = #chan :nick1 nick2
        # ---------------------------------------------------------------------
        if cmd == "353" and len(params) >= 3:
            channel = params[2]
            idx = line.find(" :")
            names = line[idx + 2 :].split() if idx != -1 else []
            with self._lock:
                self.userlist[channel] = [n.lstrip("@+%") for n in names]
            return

        # ---------------------------------------------------------------------
        # Numeric error replies indicating JOIN failed / cannot join
        # common codes: 403, 471, 473, 474, 475, 477
        # ---------------------------------------------------------------------
        if cmd in ("403", "471", "473", "474", "475", "477"):
            with self._lock:
                self.last_error = f"join_failed:{line}"
            print(f"irc_client: server reported join failure: {line}")
            return

        # ---------------------------------------------------------------------
        # 433 (nick in use) -> attempt to append underscore
        # ---------------------------------------------------------------------
        if cmd == "433":
            self._send_line(f"NICK {self.nick}_")
            self.nick = self.nick + "_"
            return

# ---------------------------------------------------------------------
# MSXPi command wrappers — module-level functions
# ---------------------------------------------------------------------

def irc_connect(params: str) -> str:
    parts = params.strip().split()
    if len(parts) < 1:
        return "usage: irc_connect <server> [port] [nick]"
    server = parts[0]
    port = int(parts[1]) if len(parts) >= 2 else 6697
    nick = parts[2] if len(parts) >= 3 else "msx"
    ok, msg = _client.connect(server, port, nick, use_ssl=True)
    return f"{'ok' if ok else 'err'}:{msg}"

def irc_disconnect(params: str) -> str:
    ok, msg = _client.disconnect()
    return f"{'ok' if ok else 'err'}:{msg}"

def irc_join(params: str) -> str:
    channel = params.strip()
    if not channel:
        return "usage: irc_join <#channel>"
    ok, msg = _client.join(channel)
    if not ok:
        return f"err:{msg}"
    deadline = time.time() + 3.0
    while time.time() < deadline:
        with _client._lock:
            if channel in _client.joined:
                try:
                    _client._send_line(f"NAMES {channel}")
                except Exception:
                    pass
                return "ok:joined"
            le = _client.last_error
        if le and "join_failed" in le:
            return f"err:{le}"
        time.sleep(0.1)
    return "err:join_timeout"

def irc_list_channels(params: str) -> str:
    chans = _client.list_channels()
    return " ".join(chans) if chans else "none"

def irc_list_users(params: str) -> str:
    channel = params.strip()
    if not channel:
        return "usage: irc_list_users <#channel>"
    users = _client.list_users(channel)
    return " ".join(users) if users else "none"

def irc_read_unread(params: str) -> str:
    print("irc_read_unread()")
    channel = params.strip()
    msgs = _client.read_all_unread(channel)
    if not msgs:
        return "none"
    lines = [f"{msg.nick}: {msg.text}" for msg in msgs]
    print(f"irc_read_unread: returning {len(lines)} messages")
    return "\n".join(lines)

def irc_send(params: str) -> str:
    parts = params.strip().split(" ", 1)
    if len(parts) < 2:
        return "usage: irc_send <target> <message>"
    target, text = parts
    ok, msg = _client.say(target, text)
    return f"{'ok' if ok else 'err'}:{msg}"

# Singleton client
_client = IRCClient()