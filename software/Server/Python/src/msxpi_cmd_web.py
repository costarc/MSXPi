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

from __future__ import annotations

from typing import Optional

# Standard library imports
import logging
import socket

# Third-party imports
import requests

logger = logging.getLogger("msxpi")

from msxpi_const import (
    CommandResult,
    HTTP_TIMEOUT,
    RC_FAILED,
    RC_SUCCESS,
    RC_SUCCNOSTD,
)
from msxpi_blocks import sendmultiblock
from msxpi_settings import getMSXPiVar

# irc
channel = "#msxpi"
allchann = []
ircsock = None

OPENAI_DEFAULT_MODEL = "gpt-4o-mini"


def chatgpt(query: str) -> CommandResult:
    print(query)
    api_key = getMSXPiVar("OPENAIKEY")
    if not api_key or api_key == "Your OpenAI API Key":
        print(
            "Pi:Error - OPENAIKEY is not defined. Define your key with PSET or add to msxpi.ini"
        )
        sendmultiblock(
            b"Pi:Error - OPENAIKEY is not defined. Define your key with PSET or add to msxpi.ini"
        )
        return RC_FAILED

    # Model comes from msxpi.ini (var OPENAIMODEL), so it can be changed with
    # `p set OPENAIMODEL <name>` as OpenAI retires models and adds new ones,
    # without touching this file. Unset or empty: fall back to the default.
    model_engine = getMSXPiVar("OPENAIMODEL").strip() or OPENAI_DEFAULT_MODEL
    url = "https://api.openai.com/v1/chat/completions"

    try:
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }

        payload = {
            "model": model_engine,
            "messages": [{"role": "user", "content": query}],
        }

        response = requests.post(
            url, headers=headers, json=payload, timeout=HTTP_TIMEOUT
        )
        openai_response = response.json()
        if "choices" in openai_response:
            response_text = openai_response["choices"][0]["message"]["content"]
            sendmultiblock(response_text.encode())
        else:
            # No completion: the API replied with an error object (or something
            # unexpected). It is a dict, so turn it into text before sending.
            api_error = (
                openai_response.get("error")
                if isinstance(openai_response, dict)
                else None
            )
            if isinstance(api_error, dict):
                detail = api_error.get("message") or str(api_error)
            elif api_error:
                detail = str(api_error)
            else:
                detail = str(openai_response)
            print("Pi:Error - " + detail)
            sendmultiblock(("Pi:Error - " + detail).encode("ascii", errors="replace"))
    except Exception as e:
        error_msg = f"Pi:Error - {str(e)}"
        print(error_msg)
        sendmultiblock(error_msg.encode())


def renderpage(parms: Optional[str] = None) -> CommandResult:
    # Parameters are already in the command packet, as for stock()/irc().
    # Always send one binary response or one short, explicitly failed response.
    try:
        from msxpi_renderpage import handle_command

        payload = handle_command(parms or "")
    except Exception as exc:
        print(f"renderpage: {exc}")
        detail = (str(exc).splitlines() or [type(exc).__name__])[0]
        message = ("showpage: " + detail)[:240]
        return sendmultiblock(message.encode("ascii", "replace"), RC_FAILED)
    if not payload:
        # scroll at the top or bottom: nothing to draw.
        return sendmultiblock(b"END", RC_SUCCNOSTD)
    return sendmultiblock(payload)


# showpage is the public command name used by the combined `p` client.
showpage = renderpage


def template(parms: Optional[str] = None) -> CommandResult:

    # This method is a template for new commands
    #

    # If your MSX command send parameters, we go read them:
    if parms == None or parms == "":
        print(f"Sending error message")
        rc = sendmultiblock("This command requires a parameter".encode())
        return

    response = f"Response from MSXPi: I received parameter '{parms}'"
    print(f"Sending back: {response}")
    rc = sendmultiblock(response.encode())

    return


def pchess(parms: Optional[str] = None) -> CommandResult:
    try:
        from msxpi_pchess import handle_command

        irc_config = {
            key: getMSXPiVar(key)
            for key in (
                "IRCADDR",
                "IRCPORT",
                "IRCNICK",
                "IRCTLS",
                "IRCACCOUNT",
                "IRCPASSWORD",
            )
        }
        payload = handle_command(parms or "", irc_config=irc_config)
    except ImportError:
        payload = bytearray(256)
        payload[:4] = b"PCH1"
        message = b"Install requirements-pchess.txt on server"
        payload[72 : 72 + len(message)] = message
    return sendmultiblock(bytes(payload))


def irc(parms: str) -> CommandResult:

    global ircsock

    # ------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------
    def sendmsg(text: str, rc=RC_SUCCESS):
        sendmultiblock(text.encode(), rc)

    def not_connected():
        sendmsg("Pi:Er:Not connected", RC_SUCCNOSTD)
        return RC_SUCCNOSTD

    # ------------------------------------------------------------
    # Decode command
    # ------------------------------------------------------------
    if not parms:
        cmd = ""
    else:
        if isinstance(parms, (bytes, bytearray)):
            cmd = parms.decode(errors="ignore").strip().lower()
        else:
            cmd = str(parms).strip().lower()

    ircserver = getMSXPiVar("IRCADDR")
    ircport = int(getMSXPiVar("IRCPORT"))
    msxnick = getMSXPiVar("IRCNICK")

    try:
        # ------------------------------------------------------------
        # CONNECT
        # ------------------------------------------------------------
        if cmd.lower().startswith("conn"):
            print("[irc] CONNECT")
            parts = cmd.split()
            jnick = parts[1] if len(parts) > 1 else msxnick
            if jnick == "none":
                jnick = msxnick

            # Close previous
            if ircsock is not None:
                try:
                    ircsock.close()
                except Exception as e:
                    print(f"[irc] error closing previous socket: {e}")

            try:
                s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                s.connect((ircserver, ircport))
            except Exception as e:
                print(f"[irc] connect exception: {e}")
                ircsock = None
                sendmsg("Pi:Er:Connect error: " + str(e), RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            ircsock = s
            ircsock.setblocking(False)

            user_line = f"USER {jnick} 0 * :{jnick}\r\n"
            nick_line = f"NICK {jnick}\r\n"
            ircsock.send(user_line.encode())
            ircsock.send(nick_line.encode())

            sendmsg("Pi:Ok:Connected to " + ircserver, RC_SUCCNOSTD)
            return RC_SUCCNOSTD

        # ------------------------------------------------------------
        # SEND MESSAGE
        # ------------------------------------------------------------
        elif cmd.startswith("say"):
            print("[irc] MSG")
            if ircsock is None:
                return not_connected()

            raw = parms[4:].strip()

            parts = raw.split(maxsplit=1)
            if len(parts) == 2:
                target, text = parts
            else:
                sendmsg("Pi:Er:Bad format", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            # Detect /names
            if text.lower().startswith("/names"):
                print("[irc] /names")
                try:
                    line = f"NAMES {target}\r\n"
                    print(f"[irc] >> {line!r}")
                    ircsock.send(line.encode())
                except Exception as e:
                    print(f"[irc] NAMES send exception: {e}")
                    sendmsg("Pi:Er:NAMES error: " + str(e), RC_SUCCNOSTD)
                    return RC_SUCCNOSTD

                sendmsg("Pi:Ok:NAMES sent", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            # Normal SAY → PRIVMSG
            try:
                line = f"PRIVMSG {raw}\r\n"
                ircsock.send(line.encode())
            except Exception as e:
                print(f"[irc] send exception: {e}")
                sendmsg("Pi:Er:Send error: " + str(e), RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            # sendmsg("Pi:Ok:Sent", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

        # ------------------------------------------------------------
        # JOIN
        # ------------------------------------------------------------
        elif cmd.lower().startswith("join"):
            print("[irc] JOIN")
            if ircsock is None:
                return not_connected()

            parts = cmd.split()
            if len(parts) < 2:
                sendmsg("Pi:Er:Missing channel", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            chan = parts[1]
            try:
                line = f"JOIN {chan}\r\n"
                ircsock.send(line.encode())
            except Exception as e:
                print(f"[irc] join exception: {e}")
                sendmsg("Pi:Er:Join error: " + str(e), RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            sendmsg("Pi:Ok:Joined", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

        # ------------------------------------------------------------
        # READ
        # ------------------------------------------------------------
        elif cmd.lower().startswith("read"):
            print("[irc] READ")
            if ircsock is None:
                sendmsg("Pi:Er:Not connected", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            try:
                data = ircsock.recv(2048)
            except BlockingIOError:
                sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                return RC_SUCCNOSTD
            except Exception as e:
                print(f"[irc] recv exception: {e}")
                sendmsg("Pi:Er:Read error: " + str(e), RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            if not data:
                sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            raw = data.decode(errors="ignore")
            if not raw.strip():
                sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                return RC_SUCCNOSTD

            lines = raw.replace("\r", "").split("\n")
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                print(f"[irc] line='{line}'")

                # PING
                if line.startswith("PING :"):
                    token = line[6:]
                    print(f"[irc] PING detected, token={token!r}")
                    try:
                        pong = f"PONG :{token}\r\n"
                        ircsock.send(pong.encode())
                    except Exception as e:
                        print(f"[irc] PONG send exception: {e}")
                    sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                    return RC_SUCCNOSTD

                # NAMES reply (353)
                if " 353 " in line:
                    print("[irc] NAMES list detected")
                    # Example: :server 353 msxpi = #openmsx :nick1 nick2 nick3
                    try:
                        parts = line.split(" :", 1)
                        if len(parts) == 2:
                            users = parts[1]
                            sendmsg("Pi:Ok:Users " + users, RC_SUCCESS)
                            print(f"[irc] NAMES parsed: users={users!r}")
                            return RC_SUCCESS
                    except Exception as e:
                        print(f"[irc] NAMES parse exception: {e}")
                        sendmsg("Pi:Ok:Users", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                # End of NAMES list (366) - housekeeping marker only, no
                # content for the user to see, so RC_SUCCNOSTD like the
                # other "nothing interesting" acks (e.g. "NAMES sent")
                if " 366 " in line:
                    sendmsg("Pi:Ok:EndUsers", RC_SUCCNOSTD)
                    return RC_SUCCNOSTD

                # JOIN reply from server
                if " JOIN " in line:
                    print("[irc] JOIN")
                    try:
                        # Example: :msxpi!~msxpi@host JOIN #openmsx
                        # With extended-join capability, the server can
                        # append more fields after the channel (account
                        # name, then :realname) - take only the first
                        # whitespace-delimited token so those don't leak
                        # into the channel name shown to the user.
                        prefix, rest = line[1:].split(" ", 1)
                        nick = prefix.split("!", 1)[0]
                        chan = rest.split("JOIN", 1)[1].strip().split(" ", 1)[0]
                    except Exception as e:
                        print(f"[irc] JOIN parse exception: {e}")
                        sendmsg("Pi:Ok:Joined", RC_SUCCESS)
                        return RC_SUCCESS

                    # If it's our own JOIN
                    if nick.lower() == msxnick.lower():
                        sendmsg(f"Pi:Ok:Joined {chan}", RC_SUCCESS)
                        return RC_SUCCESS

                    # Someone else joined the channel
                    sendmsg(f"Pi:Ok:{nick} joined {chan}", RC_SUCCESS)
                    return RC_SUCCESS

                # Registration complete (end of MOTD)
                if "End of message of the day" in line:
                    irc_registered = True
                    sendmsg("Pi:Ok:Ready", RC_SUCCNOSTD)
                    return RC_SUCCNOSTD

                # PRIVMSG
                if " PRIVMSG " in line:
                    print("[irc] PRIVMSG")
                    try:
                        prefix, rest = line[1:].split(" ", 1)
                        nick = prefix.split("!", 1)[0]
                    except Exception as e:
                        sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                    if " :" not in rest:
                        sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                    before, text = rest.split(" :", 1)
                    parts = before.split()
                    if len(parts) < 2 or parts[0].upper() != "PRIVMSG":
                        sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                    target = parts[1]
                    if msxnick in target:
                        target = "private"

                    # CTCP requests (VERSION, PING, TIME, CLIENTINFO, etc.)
                    # are wrapped in \x01...\x01 - these are automated
                    # client-fingerprinting probes from bots/clients, not
                    # real chat content, so don't surface them. CTCP ACTION
                    # (/me) is real content though - unwrap and show that.
                    if text.startswith("\x01"):
                        ctcp = text.strip("\x01")
                        if ctcp.upper().startswith("ACTION "):
                            text = "* " + nick + " " + ctcp[7:]
                            sendmsg("Pi:Ok:<" + target + "> " + text, RC_SUCCESS)
                            return RC_SUCCESS
                        sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
                        return RC_SUCCNOSTD

                    formatted = f"<{target}> {nick} -> {text}"
                    sendmsg("Pi:Ok:" + formatted, RC_SUCCESS)
                    return RC_SUCCESS

            sendmsg("Pi:Ok:No messages", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

        # ------------------------------------------------------------
        # QUIT
        # ------------------------------------------------------------
        elif cmd.lower().startswith("quit") or cmd.lower().startswith("part"):
            print("[irc] QUIT/PART")
            if ircsock is not None:
                try:
                    ircsock.send(b"QUIT\r\n")
                    ircsock.close()
                except Exception as e:
                    print(f"[irc] quit/close exception: {e}")
                ircsock = None

            sendmsg("Pi:leaving room", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

        # ------------------------------------------------------------
        # UNKNOWN
        # ------------------------------------------------------------
        else:
            print(f"[irc] UNKNOWN command: {cmd!r}")
            sendmsg("Pi:No valid command received", RC_SUCCNOSTD)
            return RC_SUCCNOSTD

    except Exception as e:
        print("[irc] Caught top-level exception:", e)
        sendmsg("Pi:" + str(e), RC_SUCCNOSTD)
        return RC_SUCCNOSTD
