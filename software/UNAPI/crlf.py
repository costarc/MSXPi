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

"""Rewrite a text file the way MSX-DOS 1 needs to read it.

Used for INL.CFG.  InterNestor Lite reads that file back through its own
command parser after installing, one line at a time.  Two separate conventions
have to be honoured, and getting either wrong produces the SAME symptom:
"*** Cannot execute this command from a configuration file" once, followed by
INL's banner repeating for ever - which looks exactly like a hang in whatever
UNAPI driver is underneath it.

1. CRLF line endings.  READ_LINE terminates a line only on CR (13); LF is not
   a terminator, so an LF-only file is swallowed as one enormous line.

2. A trailing #1A (Ctrl-Z).  This is the one that bites on MSX-DOS 1 ONLY, and
   it is why the same file works from a Nextor/DOS 2 card and loops on a DOS 1
   boot.  READ_LINE detects end of file by finding a #1A byte and by nothing
   else:

        ld  a,(DUMMY)
        cp  #1A
        ret z

   Under DOS 2 INL reads through byte-exact file handles, so it reaches a real
   end of file and stops regardless.  Under DOS 1 it falls back to its own FCB
   layer (OPEN1 -> _FOPEN), and FCB reads are 128-BYTE RECORD based - there is
   no byte-exact end.  Past the real content INL is handed the rest of the
   record and then whatever follows, indefinitely, and FIN escapes its config
   loop only on an EMPTY line, which never comes.

   So the CP/M-era text-file convention is not optional here: without the
   Ctrl-Z, INL cannot tell where a config file ends on MSX-DOS 1.
"""
import sys

data = open(sys.argv[1], "rb").read()
data = data.replace(b"\r\n", b"\n").replace(b"\n", b"\r\n")
data = data.rstrip(b"\x1a")          # never append a second one
if not data.endswith(b"\r\n"):       # a final line with no terminator is
    data += b"\r\n"                  # otherwise fused onto the Ctrl-Z
data += b"\x1a"
open(sys.argv[2], "wb").write(data)
