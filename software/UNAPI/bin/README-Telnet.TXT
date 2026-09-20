# TELNET v1.34

(c)2019-2020 Oduvaldo Pavan Junior - ducasp@gmail.com

# CHANGELOG v1.34
    - HispaMSX BBS is celebrating its 15th anniversary! So do we, this version
      is dedicated to Hispa! Thanks Karloch and everyone else involved for all
      your hard work!
    - TelnetF no longer uses fossil, being faster and smoother, so it has a
      great performance with BaDCaT
    - As a bonus, better X and Y Modem support for BaDCaT, also working on
      Hispa MSX as well :)
    - Also now supports Auto Flow control if the UART on BaDCaT supports it
    - Fixed crashing on exit on a MSX1
    - MSX1 Logic was flawed if 40 columns was set, leading it to think it was
      on 80 columns
    - By default will load a CP437 font if a MSX1 is detected, font was kindly
      provided by Piter Punk, thanks! Original font should be restored on exit,
      if you wish to keep using your MSX resident font use c switch, i.e.:
          telnet bbs.hispamsx.org c

# CHANGELOG v1.33
    - Farewell GZip, thanks for being with us in v1.32, time to rest friend!
    - Incorporate revision 1.7 of MSX2ANSI library, this will work around the
      issue created by Synchronet team that decided it is cool to send XTerm
      specific scape codes to terminals that report to be ANSI only
    - First release of a version that work with Zimodem ESP8266 firmware on
      Andrés Ortiz BadCat WiFi modem (it is not UNAPI based, it is working
      with FOSSIL driver), to use with it use TELNETF instead of TELNET

# CHANGELOG v1.32 - GZip Edition
    - New version of MSX2ANSI library with better compatibility with nCurses
      applications running on host, changes in lib by PiterPunk
    - New version of MSX2ANSI library also fixes CSIJ behavior, fix done by me
    - New version of MSX2ANSI library allows to disable cursor while rendering
      text, this should get better speed on a few scenarios and a smoother 
      screen rendering without cursor going all over the place during animation
    - Dedicated to the memory of GZip
      
# CHANGELOG v1.31
    - General code cleaning. Removing unused variables, made the negotiation
      code more efficient and better to understand, as well as fixing old
      comments that were referring to stuff no longer used :)
    - Due to the better telnet negotiation code, along with a different way to
      detect a dead connection, the flow of ANSI animation and text rendering
      is smoother, specially on regular z80 clock and with Obsonet
    - If no portnumber is given, will assume default port (23)
    - Automatic detection of BBB's that misbehave on Telnet Protocol during
      file transfers (i.e.: based on Mystic) if the transfer protocol is YModem
      or YModem-G
    - There is a significant (50%) speed-up on YModem-G transfers when the BBS
      uses the proper TELNET protocol during file transfers (i.e.: every 0xFF 
      byte is sent as 0xFF 0xFF) and the adapter allows for more than 3KB/s
      transfers (i.e.: SM-X, GR8NET... Sorry, Obsonet is not getting faster
      transfers)
    - Fixed an issue where SM-X wouldn't always properly handshake with the BBS
      during start-up, i.e.: HispaMSX wouldn't always detect terminal as ANSI
      capable

# CHANGELOG v1.30
    - Made a few behavior changes, CTRL+B won't begin downloads anymore, CTRL+E
      won't exit anymore. Those keys will now be sent over the connection which
      might be useful when acessing a linux daemon. :)
    - Now, to start a file transfer, press F1
    - Now, to exit the program, press F5
    - Now, the program by default DO NOT send CR/LF when enter is pressed, just
      CR, this makes it works with a few door games like LORD and also do not
      seem to hurt how it works with all BBS
    - Just in case just CR is giving you troubles, added possibility of changing
      CRLF behavior on the fly, press F3 to toggle it
    - Added possibility of changing ECHO behavior on the fly, press F2 to toggle
      it
    - By default, now, automatic pop-up of file transfer protocol selection will
      be disabled if the BBS send a DO BINARY in the initial handshake, the only
      type of BBS that this feature works is Synchronet, and it do not send DO 
      BINARY
    - Compiled with new version of MSX2ANSI library that supports BEEPing when
      BELL is received
        
# CHANGELOG v1.24
    - Re-compiled with new version of MSX2ANSI library. Piter Punk kindly fixed
    an issue with CSIm (no parameters) as well added support to reverse colors.
    It was crashing and also the behavior of CSIm or CSI0m was not proper. 
    Thanks Piter!
    
# CHANGELOG v1.23
    - Changed the way to handle keyboard input, Fusion-C removed support for
      the method I've used before.
    - Compiled with the new MSX2ANSI library, it fixes quite a few issues seen
      while acessing Linux or Busybox telnet servers.

# CHANGELOG v1.22
    - Reporting terminal as ANSI. Tried xterm 16 colors for a test and forgot
      to revert to ANSI. Using xterm could be bad if connecting to a host that
      is xterm aware, as this client do not implement xterm emulation

# CHANGELOG v1.21
    - Now it is possible to connect to telnet servers hosted by Linux/BSD 
      daemons, this issue was first reported by PiterPunk and then by Xipepe,
      it was caused due to some strings used during telnet negotiations being
      stored on the first page of memory that sometimes is overriden with MSX
      BIOS. This could potentially solve issues where some MSX setups would 
      have issues loading this client.

# CHANGELOG v1.20
    - ANSI-DRV.BIN is no longer externally loaded. I've converted it into a
      SDCC library, which give us a few benefits, first, performance wise it
      is a little bit better as now functions are called using a fast calling
      convention that doesn't use stack... Second, you can place it anywhere
      on your path and it will not complain about not being able to load
      ANSI-DRV.BIN... Last but not least... Having a SDCC library available
      might get more developers involved in using this great screen mode for
      many different applications. :)

# CHANGELOG v1.11

    - Oops... When changing to send arrows as ESC commands, was sending also
      0 (String terminator, not '0') after CR/LF and arrows, and this was causing 
      SlyEdit to quit even before you could type anything.  

# CHANGELOG v1.10

    - Karloch from HISPAMSX BBS told about cursor keys not working properly, so
      it seems BBS's won't understand MSX Key Codes for cursors... :) Now this
      client sends ANSI Escape codes that BBS's understand, so you can edit
      your message properly.
    
    - Also Karloch told me about how bad it is to try to edit a message without
      a cursor on the screen, you move the cursor and have no idea where it is.
      Fair enough, I've updated ANSI-DRV.BIN as well, now it has a proper
      cursor, the same color as the current text color.   

# CHANGELOG v1.00

    - jANSI is no longer used. Long history short: I've talked to Carlos
      Santana about INLCLIES (work only for internestor light) and its ANSI
      rendering was awesome, asking if I could use it. He did send me the 
      details of how it works, cool. Then I've reached the driver author, 
      Tobias Keizer (Sonic_AKA_T), and he is an awesome guy, that sent me 
      the source code of his driver and allowed me to change it and publish
      source code as well. End result: 6 seconds rendering HISPAMSX boot logo
      ANSI animation on OCM Turbo / Hardware accelerated UNAPI adapter, and 13 
      seconds at regular z80 speeds, pretty damn blazing amazing fast! So 
      Sonic_AKA_T just brought us BLAST PROCESSING from SEGA Genesis directly 
      to our MSX's 2 or greater. :) (And it is way, waaay, waaaaay faster on
      OBSONET as well really usable even at regular z80 speeds, how does 30s to 
      see HISPAMSX ANSI boot animation looks like? Remember that using jANSI
      it was 61s? :D )
    
    - As such, command line options have reduced a lot, no need to deal with 
      external ANSI drivers.
      
    - And the cool thing is, this still works with MSX1, but it will be not 
      ANSI compatible.

# CHANGELOG v0.90

    - You can use it to receive files from some BBSs that did not work 
      before, i.e.: BBSs that use Mystic software. If download do not work
      try using r command switch to enable raw file receiving (i.e.: 
      telnet bbs.telnet.org:666 r ). Those BBSs misbehave and do not 
      implement TELNET protocol correctly, not doubling FF character, and
      this switch will cause telnet to not parse received download data as
      telnet data.

    - You have option to tell terminal is ANSI even without jANSI. Perhaps
      somene has a driver for GFX9000 or something like that and want to use 
      it... Use e switch to tell that (i.e.: telnet bbs.gfx900.net:9990 e )

    - Possibility to turn off automatic download detection. Default is on, as 
      most BBSs around are Synchronet, mas other BBSs not using Synchronet 
      might use the transfer binary telnet command to send data (and as it 
      contains 8 bit characters, that is fine). This might get confusing... 
      Specially on BBSs  that hammer you with that darn transfer binary command
      every block of text they send.... Use s switch in that case (i.e.: telnet 
      bbs.noautotransfer.com:23 a )

    - Cursor is turned off by default,by using switch c you can turn cursor on.
      I just like not having the cursor showing and moving around while drawing
      ANSI screens. 
      
      Note: if using my supplied version of jANSI, you get HISPAMSX boot screen
      working fine (using cursor or not), but  without cursor it seems to draw
      a little faster and it is possible to have the screen border at the same
      color of screen background (all blue). When cursor is on, screen border 
      will always be black, even if background is a different color. (This is 
      relative to my version of jANSI and not to this software)

    - some internal improvements that allow a bit of better performance and 
      also better handling of telnet protocol, as well as responding proper 
      cursor position to ESC[6n, fixing synchronet BBSs pause when printing 
      avatars (as well the avatars and text being misplaced)

# CHANGELOG v0.80

    - Fix the program crashing when receiving two bytes TELNET commands. We do
      not execute those, but need to properly parse. It no longer crashes if
      you log-in at HISPAMSX and leave it logged/untouched
      
    - Fix on X/YMODEM(G) transfers corrupting some bytes of data
    
    - Enhancement on YMODEM(G) performance, got up to 8KB/s using MSX-SM WiFi
      UNAPI adapter
      
    - Some BBSs allow the Telnet Client to know that a transfer is in progress
      by sending Telnet command WILL TRANSFER_BINARY. Now this client is able
      to recognize it and it will pop-up the transfer protocol selection 
      automatically. If the BBS do not send WILL TRANSFER_BINARY, you still 
      can invoke the transfer protocol selection
      
    - Fix YMODEM/YMODEM-G not detecting the end of a batch or single file
      transfer properly. Now it detects properly. Exception is HISPAMSX when
      using YMODEM-G (you need to lie to it telling you want YMODEM as it does
      not list YMODEM-G as an option, so you tell it you are going to download
      YMODEM, configure your user options with YMODEM as preferred protocol, 
      and when downloading a batch ou single file choose YMODEM but on the 
      telnet client you choose YMODEM-G and the transfer will occur as YMODEM
      G, which is a blessing as XMODEM and YMODEM use 128 bytes long blocks at
      HISPA which is really slow, not sure why they do not enable 1K blocks)
      
    - ESC no longer quits the program, as this key might be requested to 
      interact with some BBSs. Now, to quit the program hit CTRL+ESC
      
    - It should now work fine with MSX1 as long as you have an UNAPI adapter 
      that works with it. It will understand that it is a MSX1 and not try to
      set 80 columns mode, but set it to 40 columns if less are set. Also, on
      MSX 2/2+/TR it will set the screen to 80 columns if less are set and 
      jANSI is not installed (with jANSI, it always use 80x25). BBSs will be
      aware that terminal is 40x24 or 80x24. Also, if you have a MSX-1 with
      an 80 columns adapter that reports properly the number of columns in use,
      this software will not try to change anything so it should work on those
      as well
      
    - Instead of returning the real cursor position on 6n escape code, it will
      return 25x80 as some BBSs use this information to determine terminal 
      window size
      
    - Not really an update, it was alway like that, but just making sure it is
      clear, jANSI/MEMMAN is not mandatory. It will work without it, but it is
      not going to tell the other end it is ANSI and of course colors and ANSI
      animations won't work.    

# DESCRIPTION

This is a TELNET client that allow you to connect to a TELNET server / BBSs and
interact with it. If an MSX2 or better is used, it will be able to receive and 
show ANSI escape codes / colors. It should be MSX1 friendly as long as your 
UNAPI adapter is compatible with MSX1.

How is it different than TCPCON? Why not keep using it?

    - It implement telnet negotiations, as such, echo is used as the other end
      requests (no need to turn on or off manually), tell terminal type (Dumb
      if MSX1 or xterm 16 colors otherwise), tell window size as 40x24 (MSX1) 
      or 80x24 (MSX1 with external 80 columns adapter and screen set to 80
      columns before executing this software) or 80x25 if MSX2 or better.
      
    - If using MSX2 or better, ANSI capabilities are automatically detected by
      most BBSs either by telnet negotiation of Window Size or responding to 
      ANSI request to cursor position (some BBS's use this to detect if 
      terminal is ANSI capable)
    
    - If using MSX2 or better, it will use MS-DOS character set, which allow 
      seeing ANSI animations and menus as they are
      
    - It supports receiving files through XMODEM CRC, XMODEM 1K CRC, YMODEM and
      YMODEM-G, including file batch in YMODEM/YMODEM-G
      
As a result, ANSI redering is real fast, on an OCM running at turbo speed it
will be faster (less than 6s) than a MSX TURBO-R using built-in telnet client 
of GR8NET to draw the MSX boot animation of HISPAMSX BBS. It also draws menus 
of ANSI BBSs really really fast at z80 turbo speeds. When using with regular 
z80 speeds it is very usable, taking a couple of seconds to draw ANSI menus and
13s to draw the MSX boot animation of HISPAMSX BBS (H/W accelerated adapters,
OBSONET uses a lot of z80 resources so it is slower). 

As a reference TCPCON with jANSI takes 35s (vs. 6s) to draw HISPAMSX boot at
OCM turbo speed (and it is 85s vs. 13s at regular z80 speeds) on a MSX-SM with
ESP8266. On BlueMSX using "OBSONET", HISPAMSX at regular z80 speeds TCPCON take
150s vs 29s using this client (OBSONET uses lots of z80 CPU resources as it is
not using TCP/IP hardware acceleration, DENYONET and GR8NET should have better
results).

# USAGE

telnet server:port [a] [r] [o] [c]

server:port: 192.168.0.1:23 or bbs.hispamsx.org:23

(NOTE: :port is now optional, and if it is not provided, will assume default 
telnet port, 23)

a - Will turn off automatic file download detection. It works on all Synchronet
BBS's and doesn't interfere on many others. But a few BBSs over use the Binary
transfer command and this could cause the protocol pop-up to show a lot of 
times. In this case, just use the a switch to de-activate this feature.

r - Some BBS's do file transfer over telnet the wrong way, not replacing 0xFF
bytes to 0xFF 0xFF (double 0xFF). This is not compliant to Telnet specs. If 
file transfer do not work, try using this switch.

o - turns off ANSI rendering and uses MSX DOS text rendering (slow, no colors,
why someone would do it on a MSX2 or better? :)

c - turns off custom CP437 that is loaded ONLY when a MSX1 is detected

Example to connect to rainmaker:

telnet rainmaker.wunderground.com:23

Most keys and CTRL+KEY combinations are sent to the telnet server.

To exit the program, press F5.

By default, echo is ON if server do not negotiate echo, and it will be ON or
OFF following the server negotiation request. If for some reason that do not
work, you can press F2 to change the current echo state.

By default, program will send only CR upon pressing ENTER. If that doesn't work
for the server/BBS you are using, press F3 to change this behavior (there are
two possible behaviors: default, send only CR, non-default, send CR-LF).

To use the file download capabilities of this telnet client, once the server is
ready to send files, press F1 and then type the filename if XMODEM is being
used, or Y if it is a YMODEM transfer, or G for YMODEM-G. On some BBS's (i.e.
Synchronet BBSs) you do not need to do this as they send a telnet command that
warns a binary data transfer is starting, so the list of protocol options pops
up automatically.

My recommendation is YMODEM-G, it is way faster due to not having to wait for
client confirmation before sending the next packet. Most BBS's, like HISPAMSX,
even though not listing YMODEM-G as an option, will use YMODEM-G if you choose
YMODEM at the BBS end and YMODEM-G after pressing CTRL+B.

***WARNING***

I just have an OCM like MSX ( MSX-SM by Victor Trucco ) and I'm using its built
in WiFi capabilities with a customized ESP8266 firmware and an UNAPI driver 
made by me. My other option to test this is using BlueMSX OBSONET emulation. So
I've not tested it with other UNAPI adapters, but it should work fine. :)

***KNOWN ISSUES***

    - XMODEM and YMODEM(G) transfers are a work in progress, at this moment it
      works on some BBSs, on others it just error. If you get errors, let me 
      know the file/BBS.
      
    - XMODEM and YMODEM performance will generaly always suck, sorry! Those 
      will send an ACK to the server after receiving a block, and the server
      will wait receiving the ACK before sending the next block, so, you have
      2x the ping to the server between each block. Let's say it is using 128 
      bytes per block, and 100ms ping, 200ms between 128 bytes packets... Yeah,
      it won't work at great speeds. Using 1024 bytes packets it gets better, 
      but HISPAMSX as an example will use XMODEM and YMODEM with 128 bytes 
      packets only. (I have a 180ms ping to HISPA server, so in my case this 
      means ~350 bytes per second!) Use YMODEM-G if possible, it streams and 
      is not ping/lag dependent, and most BBSs, even if not listing YMODEM-G,
      work with it if you choose YMODEM at BBS side and YMODEM-G on the MSX
      side. 

***IMPORTANT COMPILATION NOTES***

Remember to copy the files in fusion-c\lib and fusion-c\header to your fusion-c lib and header folders!
You will need the following libraries:

    - Konamiman's ASM.LIB ( https://www.konamiman.com/msx/sdcc/asmlib.zip )
    - Oduvaldo & Tobias Keizer MSX2ANSI.LIB ( https://github.com/ducasp/MSX-Development/tree/master/SDCC/MSX2ANSI )

I recommend using Code::Blocks, it is a full featured UI that will allow you to check references, etc.

Redistribution and use of this source code or any derivative works, are
permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. Redistributions may not be sold, nor may they be used in a commercial
   product or activity without specific prior written permission.
4. Source code of derivative works MUST be published to the public.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS;
OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
