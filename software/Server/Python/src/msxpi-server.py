#!/usr/bin/python3
"""-----------------------------------------------------------------------------------
MIT License

Copyright (c) 2016 - 2025 Ronivon Costa

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
-----------------------------------------------------------------------------------"""
# External module imports

from fileinput import filename
from tarfile import BLOCKSIZE
import time
import subprocess
from urllib.request import urlopen
import requests
import mmap
# import fcntl # does not work in Windows
import os
import sys
import platform
from os.path import exists
from subprocess import Popen,PIPE,STDOUT
from html.parser import HTMLParser
import datetime
import time
import glob
import array
import socket
import errno
import select
import base64
import math
from random import randint
from fs import open_fs
import threading
from io import StringIO
from contextlib import redirect_stdout
import shutil

version = "1.3"
BuildId = "20251016.005"

CMDSIZE = 9
MSGSIZE = 128
BLKSIZE = 512
SECTORSIZE = 512
BULKBLKSIZE = 3 + 4096
MAXBUFSIZE = 48*1024       # 48 KB buffer in the MSX side

SPI_SCLK_LOW_TIME = 0.001
SPI_SCLK_HIGH_TIME = 0.001

GLOBALRETRIES       = 10
MAX_BLOCK_RETRIES   = 3
SPI_INT_TIME        = 3000
PIWAITTIMEOUTOTHER  = 120     # seconds
PIWAITTIMEOUTBIOS   = 60      # seconds
SYNCTIMEOUT         = 15
BYTETRANSFTIMEOUT   = 15
SYNCTRANSFTIMEOUT   = 15.0
DISABLETIMEOUT      = False
READY_ACK           = 0xA0
SENDNEXT            = 0xA1
ENDTRANSFER         = 0xA2
READY               = 0xAA
RC_CHKSUM_ERR       = 0xAD
WAIT                = 0xAE

RC_SUCCESS          =    0xE0
RC_INVALIDCOMMAND   =    0xE1
RC_ESCPRESSED       =    0xE2
RC_BUFOVFLW         =    0xE3
RC_INVALIDDATASIZE  =    0xE4
RC_HANDSHAKEERR     =    0xE5
RC_FILENOTFOUND     =    0xE6
RC_FAILED           =    0xE7
RC_CONNERR          =    0xE8
RC_WAIT             =    0xE9
RC_READY            =    0xEA
RC_SUCCNOSTD        =    0xEB
RC_FAILNOSTD        =    0xEC
RC_TERMINATE        =    0xED
RC_UNEXPECTEDDATA   =    0xEE
RC_UNDEFINED        =    0xEF

st_init             =    0       # waiting loop, waiting for a command
st_cmd              =    1       # transfering data for a command
st_recvdata         =    2
st_senddata         =    4
st_synch            =    5       # running a command received from MSX
st_runcmd           =    6
st_shutdown         =    99

NoTimeOutCheck      = False
TimeOutCheck        = True

MSXPIHOME = "/home/pi/msxpi"
RAMDISK = "/media/ramdisk"
TMPFILE = RAMDISK + "/msxpi.tmp"

# irc
channel = "#msxpi"
allchann = []
ircsock = None
errcount = 0
msxdos1boot = False

HOST = '0.0.0.0'  # Listen on all interfaces
PORT = 5000       # Match this with serverPort in your C++ code
conn = None

hostType = "RaspberryPi"
RPI_SHUTDOWN = 26
press_time = None

def detect_host():
    system = platform.system()
    machine = platform.machine()

    if system == "Windows":
        return "Windows"
    elif system == "Darwin":
        return "MacOS"
    elif system == "Linux":
        # Check for Raspberry Pi
        try:
            with open("/proc/cpuinfo", "r") as f:
                cpuinfo = f.read()
            if "Raspberry Pi" in cpuinfo or "BCM" in cpuinfo or "Raspberry" in platform.uname().node:
                return "RaspberryPi"
        except Exception:
            pass
        return "Linux"
    else:
        return system

def init_spi_bitbang():
# Pin Setup:
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(SPI_CS, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(SPI_SCLK, GPIO.OUT)
    GPIO.setup(SPI_MOSI, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
    GPIO.setup(SPI_MISO, GPIO.OUT)
    GPIO.setup(RPI_READY, GPIO.OUT)
    GPIO.setup(RPI_SHUTDOWN, GPIO.IN, pull_up_down=GPIO.PUD_UP)

def tick_sclk():

    global SPI_SCLK
    GPIO.output(SPI_SCLK, GPIO.HIGH)
    time.sleep(0.00001)
    GPIO.output(SPI_SCLK, GPIO.LOW)

def SPI_ByteTransfer(byte_out=None):
    
    global conn, hostType
    byte_in = 0    
    if hostType == "RaspberryPi":
        # GPIO-based SPI emulation
        global SPI_CS, RPI_READY

        GPIO.output(RPI_READY, GPIO.HIGH)
        while GPIO.input(SPI_CS):
            pass

        tick_sclk()
        for bit in [0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01]:
            # Send bit if byte_out is provided
            if byte_out is not None:
                GPIO.output(SPI_MISO, GPIO.HIGH if (byte_out & bit) else GPIO.LOW)
            else:
                GPIO.output(SPI_MISO, GPIO.LOW)  # Passive receive mode

            GPIO.output(SPI_SCLK, GPIO.HIGH)

            # Always read MOSI
            if GPIO.input(SPI_MOSI):
                byte_in |= bit

            GPIO.output(SPI_SCLK, GPIO.LOW)

        tick_sclk()
        GPIO.output(RPI_READY, GPIO.LOW)
    else:
        if DISABLETIMEOUT == True:
            #print("disabling timeout")
            conn.settimeout(None)
        else:
            #print("enabling timeout")
            conn.settimeout(SYNCTRANSFTIMEOUT)
        if byte_out is not None:
            # print("SPI_ByteTransfer(): Non-Raspberry Pi conn.sendall")
            conn.sendall(bytes([byte_out]))
            #print(f"Sent: {chr(byte_out)}")
            #print(f"Sent: {chr(byte_out)}")
        else:
            # print("SPI_ByteTransfer(): Non-Raspberry Pi conn.recv")
            try:
                #byte_in = conn.recv(1)[0]  # Passive receive mode
                buf = conn.recv(1)
                if buf == b'':   # connection closed
                    print("SPI_ByteTransfer(): connection closed by peer")
                    return RC_CONNERR, None
                byte_in = buf[0]
            except socket.timeout:
                print("SPI_ByteTransfer(): recv timed out")
                return RC_FAILED,None
            except IndexError:
                print("SPI_ByteTransfer(): e-connection closed by peer")
                return RC_CONNERR, None

    
            #print(f"Received: {chr(byte_in)}")
    return RC_SUCCESS,byte_in
    
# create a subclass and override the handler methods
class MyHTMLParser(HTMLParser):
    def __init__(self):
        self.reset()
        self.NEWTAGS = []
        self.NEWATTRS = []
        self.HTMLDATA = []
    def handle_starttag(self, tag, attrs):
        self.NEWTAGS.append(tag)
        self.NEWATTRS.append(attrs)
    def handle_data(self, data):
        self.HTMLDATA.append(data)
    def clean(self):
        self.NEWTAGS = []
        self.NEWATTRS = []
        self.HTMLDATA = []
    def convert_charrefs(self, data):
        print("MyHTMLParser: convert_charrefs found :", data)
                
def pathExpander(path, basepath = ''):
    #print(f"pathExpander()")
    
    path=path.strip().rstrip(' \t\n\0')
    
    if path.strip() == "..":
        path = basepath.rsplit('/', 1)[0]
        basepath = ''
    if len(path) == 0 or path == '' or path.strip() == "." or path.strip() == "*":
        path = basepath
        basepath = ''
    if path.startswith('/'):
        urltype = 0 # this is an absolute local path
        newpath = path
    elif (path.lower().startswith('m:')):
        urltype = 1 # this is a network path
        newpath = getMSXPiVar('DriveM') + '/' + path.split(':')[1]
    elif (path.lower().startswith('r1:')):
        urltype = 1 # this is a network path
        newpath = getMSXPiVar('DriveR1') + '/' + path.split(':')[1]
    elif (path.lower().startswith('r2:')):
        urltype = 1 # this is a network path
        newpath = getMSXPiVar('DriveR2') + '/' + path.split(':')[1]
    elif (path.lower().startswith('http') or \
        path.lower().startswith('ftp') or \
        path.lower().startswith('nfs') or \
        path.lower().startswith('smb')):
        urltype = 1 # this is a network path
        newpath = path
    elif basepath.startswith('/'):
        urltype = 0 # this is a local path
        newpath = basepath + '/' + path
        newpath = newpath.replace('//','/')
    else:
        urltype = 1 # this is a network path
        newpath = basepath + "/" + path
    return [urltype, newpath]

def msxdos_inihrd(filename, access=mmap.ACCESS_WRITE):
    print("msxdos_inihrd()")
    
    if ('disk' in vars() or 'disk' in globals()):
        disk.flush()
    size = os.path.getsize(filename)
    if (size>0):
        fd = os.open(filename, os.O_RDWR)
        disk = mmap.mmap(fd, size, access=access)
        rc = RC_SUCCESS
    else:   
        disk = ''
        rc = RC_FAILED
    return rc,disk

def dos83format(fname):
    name = '        '
    ext = '   '

    finfo = fname.split('.')

    name = str(finfo[0]).ljust(8)
    if len(finfo) == 2:
        ext = str(finfo[1]).ljust(3)
    
    return name+ext

def ini_fcb(fname,fsize):
    print("ini_fcb()")
    
    fpath = fname.split(':')
    if len(fpath) == 1:
        msxfile = str(fpath[0])
        msxdrive = 0
    else:
        msxfile = str(fpath[1])
        drvletter = str(fpath[0]).upper()
        msxdrive = ord(drvletter) - 64

    #convert filename to 8.3 format using all 11 positions required for the FCB
    msxfcbfname = dos83format(msxfile)

    # send FCB structure to MSX
    buf = bytearray()
    buf.extend(msxdrive.to_bytes(1,'little'))
    buf.extend(msxfcbfname.encode())
    rc = sendmultiblock(buf)   
    return rc

def run(cmd = ''):
    print(f"run(): {cmd}")
    
    global hostType
    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        rc = sendmultiblock("Syntax: run <command> <::> command. To  pipe a command to other, use :: instead of |")
        return RC_FAILED

    cmd = cmd.replace('::','|')
    rc = RC_SUCCESS

    try:
        if hostType == "Windows" and "http" not in cmd:
            cmd = cmd.replace("/", "\\")

        p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
        buf = p.stdout.read().decode()
        err = (p.stderr.read().decode())
        if len(err) > 0 and not ('0K ....' in err): # workaround for wget false positive
            rc = RC_FAILED
            buf = ("Pi:Error - " + str(err))
        elif len(buf) == 0:
            rc = RC_SUCCESS
            buf = "Pi:Ok"
        sendmultiblock(buf.encode())
        return rc
    except Exception as e:
        print("run: exception:"+str(e))
        sendmultiblock(("Pi:Error - "+str(e)).encode())
        return rc

def dir(data):
    print(f"pdir():{data}")
    
    basepath = getMSXPiVar('PATH')
  
    if not data:
        userPath=''
    else:
        userPath = data
    pathType, path = pathExpander(userPath, basepath)           
    try:
        if pathType == 0:
            if hostType == "Windows":
                run('dir ' + path)
            else:
                run('ls -l ' + path)
        else:
            parser = MyHTMLParser()
            htmldata = urlopen(path).read().decode()
            parser = MyHTMLParser()
            parser.feed(htmldata)
            buf = " ".join(parser.HTMLDATA)
            rc = sendmultiblock(buf.encode())
    except Exception as e:
        sendmultiblock(('Pi:Error - ' + str(e)).encode())

    return RC_SUCCESS

def cd(data):
    print(f"pcd(): {data}")
    
    rc = RC_SUCCESS
    basepath = getMSXPiVar('PATH') 
    if not data:
        userPath=''
    else:
        userPath = data 
    try:
        if (len(userPath) == 0 or userPath == '' or userPath.strip() == "."):
            rc = sendmultiblock(basepath.encode())
        elif (userPath.strip() == ".."):
            newpath = basepath.rsplit('/', 1)[0]
            if (newpath == ''):
                newpath = '/'
            setMSXPiVar('PATH',newpath)
            rc = sendmultiblock(newpath.encode())
        else:
            pathType, path = pathExpander(userPath, basepath)
            if pathType == 0:
                if (os.path.isdir(path)):
                    setMSXPiVar('PATH',path)
                    rc = sendmultiblock(path.encode())
                else:
                    sendmultiblock("Pi:Error - not a folder".encode())
            else:
                setMSXPiVar('PATH',path)
                rc = sendmultiblock(path.encode())
    except Exception as e:
        print("pcd:"+str(e))
        sendmultiblock(('Pi:Error - ' + str(e)).encode())

    return RC_SUCCESS
    
def pcopy(msxcmd = "pcopy"):
    print("pcopy()")
    
    global psetvar,GLOBALRETRIES,hostType
    basepath = getMSXPiVar('PATH')
    rc = RC_SUCCESS
    
    # Receive parameters - but before, prepare help message to pass
    errorMsg = 'Syntax:\n'
    if msxcmd == "pcopy":
        errorMsg = errorMsg + 'pcopy </z> remotefile <localfile>\n'
    elif msxcmd == "ploadr":
        errorMsg = errorMsg + 'ploadr </z> remotefile\n'
    errorMsg = errorMsg +'Valid devices:\n'
    errorMsg = errorMsg +'/, path, http, ftp, nfs, smb, m:, r1:, r2:\n'
    errorMsg = errorMsg + '/z decompress file\n'
    errorMsg = errorMsg + 'm:, r1: r2: virtual remote devices'

    rc, data = readParameters(errorMsg, True)   
    if rc != RC_SUCCESS:
        return RC_FAILED
    if not data:
        userPath=''
    else:
        userPath = data
    fname2 = ''
    expandedFn = ''
    parms = userPath.split()
    pathType = 0
    if '/z' in userPath.lower():
        expand = True
        pathType, path = pathExpander(parms[1], basepath)
        if len(parms) > 2:
            fname2 = parms[2]
    else:
        expand = False
        if len(parms) > 1:
            pathType, path = pathExpander(parms[0], basepath)
            fname2 = parms[1]
  
        else:
            pathType, path = pathExpander(parms[0], basepath)
            if "/" in path:
                fname2=path.split("/")[len(path.split("/"))-1]
            elif ":" in path:
                fname2=path.split(":")[0]
            else:
                fname2 = path
    if pathType == 0:
        try:
            with open(path, mode='rb') as f:
                buf = f.read()
            filesize = len(buf)
        except Exception as e:
            err = 'Pi:Error - ' + str(e)
            rc = sendmultiblock(('Pi:Error - ' + str(e)).encode())
            return RC_FAILED
    else:
        try:
            urlhandler = urlopen(path)
            buf = urlhandler.read()
            filesize = len(buf)
            rc = RC_SUCCESS
        except Exception as e:
            print(f"Pi:Error - {str(e)}")
            rc = senddata(RC_FAILED, ('Pi:Error - ' + str(e)).encode())
            return RC_FAILED
    # if /z passed, will uncompress the file
    if rc == RC_SUCCESS:
        if expand:
            tmpfn0 = path.split('/')
            tmpfn = tmpfn0[len(tmpfn0)-1]
            if hostType == "Windows":
                os.system('del /Q "C:\\tmp\\msxpi\\*"')
            else:
                os.system('rm /tmp/msxpi/* 2>/dev/null')
            tmpfile = open('/tmp/' + tmpfn, 'wb')
            tmpfile.write(buf)
            tmpfile.close()
            # If not windows, uses lha to extrac lzh files
            if ".lzh" in tmpfn:
                if hostType == "Windows":
                    cmd = 'lha -xfiw=/tmp/msxpi /tmp/' + tmpfn
                else:
                    cmd = '/usr/bin/lhasa -xfiw=/tmp/msxpi /tmp/' + tmpfn
                p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
                perror = (p.stderr.read().decode())
                rc = p.poll()
                if rc!=0 and rc != None:
                    rc = RC_FAILED
            else:
                # Will use 7-Zip for any file type under Windows
                if hostType == "Windows":
                    cmd = '7z.exe e /tmp/' + tmpfn + ' -aoa -o/tmp/msxpi/'
                else:
                    cmd = '/usr/bin/unar -f -o /tmp/msxpi /tmp/' + tmpfn
                p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
                perror = (p.stderr.read().decode())
                rc = p.poll()
                if rc!=0:
                    rc = RC_FAILED
            romfiles = [f for f in os.listdir('/tmp/msxpi') if f.endswith(('.rom', '.ROM'))]
            if romfiles:
                fname1 = '/tmp/msxpi/' + romfiles[0]
                
                try:
                    with open(fname1, mode='rb') as f:
                        buf = f.read()

                    filesize = len(buf)
                    rc = RC_SUCCESS
                    
                except Exception as e:
                    rc = senddata((RC_FAILED, 'Pi:Error - ' + str(e)).encode())
                    return RC_FAILED
       
            else:
                print(f"Pi:Error - {perror}")
                rc = senddata((RC_FAILED, 'Pi:Error - ' + perror).encode())
                return RC_FAILED
    
    # If all good so far (including eventual decompress if needed)
    # then send the file to MSX
    if rc == RC_SUCCESS:
        if filesize == 0:
            rc = senddata(RC_FAILED, "Pi:Error - File size is zero bytes".encode())
            return RC_FAILED

        else:
            # Did we boot from the MSXPi ROM or another external drive?
            if (not msxdos1boot) or msxcmd == "ploadr": # Boot was from an externdal drive OR it is PLOADR
                if expand:
                    if fname2 == '':
                        rc = ini_fcb(expandedFn,filesize)
                    else:
                        rc = ini_fcb(fname2,filesize)
                else:
                    rc = ini_fcb(fname2,filesize)
                if rc != RC_SUCCESS:
                    print("pcopy: ini_fcb failed")
                    return rc
                
                # This will send the file to MSX, for pcopy to write it to disk
                rc = senddata(rc, buf)
            
            else:# Booted from MSXPi disk drive (disk images)
                # this routine will write the file directly to the disk image in RPi
                try:
                    drive = getMSXPiVar('DriveA')
                    fatfsfname = "fat:///"+getMSXPiVar('DriveA')        # Asumme Drive A:
                    if fname2.upper().startswith("A:"):
                        fname2 = fname2.split(":")
                        if len(fname2[1]) > 0:
                            fname2=fname2[1]           # Remove "A:" from name
                        elif expandedFn != '':
                            fname2 = expandedFn
                        else:
                            fname2=path.split("/")[len(path.split("/"))-1]           # Drive not passed in name
                    elif fname2.upper().startswith("B:"):
                        drive = getMSXPiVar('DriveB')
                        fatfsfname = "fat:///"+getMSXPiVar('DriveB')    # Is Drive B:
                        fname2 = fname2.split(":")
                        if len(fname2[1]) > 0:
                            fname2=fname2[1]           # Remove "B:" from name
                        elif expandedFn != '':
                            fname2 = expandedFn
                        else:
                            fname2=path.split("/")[len(path.split("/"))-1]           # Drive not passed in name
                    elif expandedFn != '':
                        fname2 = expandedFn
                    elif fname2 == '':
                        fname2=path.split("/")[len(path.split("/"))-1]

                    dskobj = open_fs(fatfsfname)
                    dskobj.create(fname2,True)
                    dskobj.writebytes(fname2,buf)
                    msxdos_inihrd(drive)
                    senddata(RC_TERMINATE, "Pi:Ok".encode())
                except Exception as e:
                    rc = senddata(RC_FAILED, ('Pi:Error - ' + str(e)).encode())

    return rc

def formatrsp(rc,lsb,msb,msg,size=BLKSIZE):
    b = bytearray(size)
    b[0] = rc
    b[1] = lsb
    b[2] = msb
    b[3:len(msg)] = bytearray(msg.encode())
    return b
    
def date(parms = None):
    print("pdate()")

    pdate = bytearray(8)
    now = datetime.datetime.now()

    # Fill buffer in MSX‑expected order
    pdate[0] = now.day
    pdate[1] = now.month
    pdate[2] = now.year & 0xFF
    pdate[3] = now.year >> 8
    pdate[4] = now.hour
    pdate[5] = now.minute
    pdate[6] = now.second
    pdate[7] = 0  # hundredths (unused)

    # -----------------------------
    # Debug print (MSX-style)
    # -----------------------------
    print("Python buffer values before sending:")
    print(f"buffer[0] Day:     {pdate[0]}")
    print(f"buffer[1] Month:   {pdate[1]}")
    print(f"buffer[2] YearLo:  {pdate[2]}")
    print(f"buffer[3] YearHi:  {pdate[3]}")
    print(f"buffer[4] Hour:    {pdate[4]}")
    print(f"buffer[5] Minute:  {pdate[5]}")
    print(f"buffer[6] Second:  {pdate[6]}")
    print(f"buffer[7] Sec100:  {pdate[7]}")

    year = pdate[2] | (pdate[3] << 8)
    print(f"Parsed Date: {pdate[0]:02d}/{pdate[1]:02d}/{year}")
    print(f"Parsed Time: {pdate[4]:02d}:{pdate[5]:02d}:{pdate[6]:02d}")

    # Now send to MSX
    sendmultiblock(pdate)

def play(data):
    print(f"pplay(): {data}")
    
    if not data:
        rc = sendmultiblock("Syntax:\npplay play|loop|pause|resume|stop|getids|getlids|list <filename|processid|directory|playlist|radio>\nExemple: pplay play music.mp3")
        return RC_FAILED
       
    if hostType != "RaspberryPi": 
        sendmultiblock("Command not supported in this platform".encode())
        return RC_SUCCESS
        
    parmslist = data.split(" ")
    cmd = parmslist[0]
    if len(parmslist) > 1:
        parms = data.split(" ")[1].split("\x00")[0]
    else:
        parms = ''

    buf = ''
    try:
        buf = subprocess.check_output(['/home/pi/msxpi/pplay.sh',getMSXPiVar('PATH'),cmd,parms])
        if buf == b'':
            buf = b'\x0a'
        sendmultiblock(buf)
    except subprocess.CalledProcessError as e:
        sendmultiblock(("Pi:Error - "+str(e)).encode())

    return RC_SUCCESS
    
def vol(data):
    print(f"pvol(): {data}")

    if not data:
        rc = sendmultiblock("This command requires a parameter")
        return RC_FAILED

    if rc == RC_SUCCESS:
        if hostType == "RaspberryPi": 
            rc = run("mixer set PCM -- " + data)
            return RC_SUCCESS
        else:
            sendmultiblock("Command not supported in this platform".encode())
    return RC_SUCCESS
    
def set(data):
    print(f"pset(): {data}")
    global psetvar, drive0Data, drive1Data

    # Normalize input
    data = data.strip()

    # ---------------------------------------------------------
    # 0. No arguments → list all variables
    # ---------------------------------------------------------
    if not data:
        out = ""
        for name, value in psetvar:
            out += f"{name}={value}\n"
        return sendmultiblock(out.encode())

    # Split into tokens
    parts = data.split()
    cmd = parts[0].lower()

    # ---------------------------------------------------------
    # 1. Global help:  set /h   set /he   set /help
    # ---------------------------------------------------------
    if cmd in ("/h", "/help"):
        helptext = (
            "Syntax:\n"
            "set                     List all variables\n"
            "set varname             Show a single variable\n"
            "set varname value       Set or update variable\n"
            "set varname /d          Delete variable\n"
            "set /h                  Show this help"
        )
        return sendmultiblock(helptext.encode())

    # Now treat first token as variable name
    varname = parts[0]
    varname_upper = varname.upper()

    # ---------------------------------------------------------
    # 2. Single variable display:  set wifi
    # ---------------------------------------------------------
    if len(parts) == 1:
        for name, value in psetvar:
            if name.upper() == varname_upper:
                return sendmultiblock(f"{name}={value}".encode())
        return sendmultiblock(f"{varname} not found".encode())

    # ---------------------------------------------------------
    # 3. Per-variable help:  set wifi /h
    # ---------------------------------------------------------
    if parts[1].lower() in ("/h", "/he", "/help"):
        helptext = (
            f"Help for variable '{varname}':\n"
            "set varname             Show variable\n"
            "set varname value       Set variable\n"
            "set varname /d          Delete variable\n"
        )
        return sendmultiblock(helptext.encode())

    # ---------------------------------------------------------
    # 4. Delete variable:  set wifi /d
    # ---------------------------------------------------------
    if parts[1].lower() in ("/d", "/delete"):
        print(f"Deleting variable {varname}")
        rc = setMSXPiVar(varname, "")  # empty value = delete
        return sendmultiblock("Pi:Ok".encode())

    # ---------------------------------------------------------
    # 5. Set or update variable:  set wifi MYSSID
    # ---------------------------------------------------------
    varvalue = data[len(varname):].strip()

    print(f"Setting variable {varname} to value {varvalue}")
    rc = setMSXPiVar(varname, varvalue)

    # Special cases for drives
    if rc == RC_SUCCESS:
        if varname_upper == 'DRIVEA':
            rc, drive0Data = msxdos_inihrd(varvalue)
            updateIniFile(MSXPIHOME + '/msxpi.ini', psetvar)

        elif varname_upper == 'DRIVEB':
            rc, drive1Data = msxdos_inihrd(varvalue)
            updateIniFile(MSXPIHOME + '/msxpi.ini', psetvar)

        return sendmultiblock("Pi:Ok".encode())

    return sendmultiblock("Pi:Error".encode())

def setMSXPiVar(pvar='', pvalue=''):
    global psetvar
    print(f"setMSXPiVar(): var={pvar} value={pvalue}")

    # Normalize name for case-insensitive matching
    pvar_upper = pvar.upper()

    # ---------------------------------------------------------
    # 1. Update or delete existing variable
    # ---------------------------------------------------------
    for i, (name, value) in enumerate(psetvar):
        if name.upper() == pvar_upper:

            # Delete variable if no value provided
            if pvalue == '':
                print(f"Deleting variable {pvar}")
                del psetvar[i]
            else:
                print(f"Updating variable {pvar} to {pvalue}")
                psetvar[i][1] = pvalue

            updateIniFile(MSXPIHOME + '/msxpi.ini', psetvar)
            return RC_SUCCESS

    # ---------------------------------------------------------
    # 2. Add new variable (dynamic growth)
    # ---------------------------------------------------------
    print(f"Adding new variable {pvar}={pvalue}")
    psetvar.append([pvar, pvalue])
    updateIniFile(MSXPIHOME + '/msxpi.ini', psetvar)
    return RC_SUCCESS

def getMSXPiVar(devname = 'PATH'):
    global psetvar
    devval = ''
    idx = 0
    for v in psetvar:
        if devname.upper() ==  psetvar[idx][0].upper():
            devval = psetvar[idx][1]
            break
        idx += 1
    return devval
    
def wifi(cmd):
    print(f"pwifi(): {cmd}")
    global psetvar
    wifissid = getMSXPiVar('WIFISSID')
    wifipass = getMSXPiVar('WIFIPWD')
    wificountry = getMSXPiVar('WIFICOUNTRY')

    if (cmd[:2] == "/h"):
        sendmultiblock("Pi:Usage:\npwifi display | set".encode())
        return RC_SUCCESS

    if (cmd[:1] == "s" or cmd[:1] == "S"):
        if hostType == "RaspberryPi":
            wifisetcmd = 'sudo nmcli device wifi connect "' + wifissid + '" password "' + wifipasss + '"'
            run(wifisetcmd)
        else:
            sendmultiblock(b'Parameter not supported in this platform')
    else:
        if hostType == "RaspberryPi":
            run("ip a | grep '^1\\|^2\\|^3\\|^4\\|inet'|grep -v inet6")
        else:
            run("ipconfig")
    
    return RC_SUCCESS

def ver(parms = None):
    print("pver()")
    global version,build
    ver = "MSXPi Server Version "+version+" Build "+ BuildId
    print("Sending version info:",ver)
    RC = sendmultiblock(ver.encode())
    print(f"pver(): returning rc = {hex(rc)}")
    return rc
    
def irc():

    print("irc()")

    global allchann,psetvar,channel,ircsock
    ircserver = getMSXPiVar('IRCADDR')
    ircport = int(getMSXPiVar('IRCPORT'))
    msxpinick =  getMSXPiVar('IRCNICK')
    
    rc,data = recvdata()
    if rc != RC_SUCCESS:
        return rc
    if data[0] == 0:
        cmd=''
    else:
        cmd = data.decode().split("\x00")[0].lower()
    rc = RC_SUCCNOSTD
    try:
        if cmd[:4] == 'conn':
            ircsock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            jparm = cmd.split(' ')
            jnick = jparm[1]
            if (jnick == 'none'):
                jnick = msxpinick
            ircsock.connect((ircserver, ircport))
            buf = bytearray()
            buf.extend(("USER "+ jnick +" "+ jnick +" "+ jnick + " " + jnick + "\r\n").encode())
            ircsock.send(buf)
            buf = bytearray()
            buf.extend(("NICK "+ jnick +"\r\n").encode())
            ircsock.setblocking(0);
            ircsock.send(buf)
            ircmsg = 'Connected to ' + ircserver
            sendmultiblock(ircmsg.encode())
        elif cmd[:3] == "msg":
            ircsock.setblocking(0);
            ircsock.send(("PRIVMSG "+cmd[4:] +"\r\n").encode())
            sendmultiblock("Pi:Ok\n".encode())
        elif cmd[:4] == 'join':
            jparm = cmd.split(' ')
            jchannel = jparm[1]
            if jchannel in allchann:
                ircmsg = 'Already joined - setting to current. List of channels:' + str(allchann).replace('bytearray(b','').replace(')','')
                channel = jchannel
            ircsock.setblocking(0);
            ircsock.send(("JOIN " + jchannel + "\r\n").encode())
            ircmsg = 'Pi:Ok\n'
            rc = RC_SUCCNOSTD
            ircsock.setblocking(0);
            sendmultiblock(ircmsg.encode())
        elif cmd[:4] == 'read':
            ircmsg = 'Pi:Error'
            try:
                ircmsg = ircsock.recv(2048).decode()
                if len(ircmsg)>1:
                    ircmsg = ircmsg.strip('\n\r')
                if ircmsg.find("PING :") != -1:
                    ircmsgList = ircmsg.split(":")
                    idx=0
                    pingReply = 'PONG'
                    for msg in ircmsgList:
                        if 'PING' in msg:
                            pingReply = ircmsgList[idx + 1]
                        idx += 1
                    ircsock.setblocking(0);
                    ircsock.send(("PONG :"+pingReply+"\r\n").encode())
                    rc = RC_SUCCNOSTD
                if ircmsg.find("PRIVMSG") != -1:
                    ircname = ircmsg.split('!',1)[0][1:]
                    ircchidxs = ircmsg.find('PRIVMSG')+8
                    ircchidxe = ircmsg[ircchidxs:].find(':')
                    ircchann = ircmsg[ircchidxs:ircchidxs+ircchidxe-1]
                    if msxpinick in ircchann:
                        ircchann = 'private'
                    ircremmsg = ircmsg[ircchidxs+ircchidxe+1:]
                    ircmsg = '<' + ircchann + '> ' + ircname + ' -> ' + ircremmsg
                    rc = RC_SUCCESS
            except socket.error as e:
                err = e.args[0]
                print("irc read exception:",err,str(e))
                ircmsg = 'Pi:Ok\n'
                rc = RC_SUCCNOSTD
            sendmultiblock(ircmsg.encode())        
        elif cmd[:5] == 'names':
            ircsock.send((cmd+"\r\n").encode())
            ircmsg = ''
            ircmsg = ircmsg + ircsock.recv(2048).decode("UTF-8")
            ircmsg = ircmsg.strip('\n\r')
            ircmsg = "Users on channel " #+ ircmsg.split('=',1)[1]
            sendmultiblock(ircmsg.encode())
        elif cmd[:4] == 'quit':
            ircsock.send(("/quit\r\n").encode())
            ircsock.close()
            sendmultiblock("Pi:leaving room\r\n".encode())
        elif cmd[:4] == 'part':
            ircsock.send(("/part\r\n").encode())
            ircsock.close()
            sendmultiblock("Pi:leaving room\n".encode())
        else:
            print("irc:no valid command received")
            sendmultiblock("Pi:No valid command received".encode())
    except Exception as e:
        print("irc:Caught exception"+str(e))
        sendmultiblock("Pi:"+str(e).encode())
        
def dosinit(parms = None):
    print("dosinit()")    
    global msxdos1boot
        
    rc,data = recvdata2()
    if rc == RC_SUCCESS:
        flag = data.decode().split("\x00")[0]
        if flag == '1':
            dskioini()
        else:
            msxdos1boot = False
 
    return rc
    
def dskioini(parms = None):
    print("dskioini()")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data
    
    # Initialize disk system parameters
    msxdos1boot = True
    sectorInfo = [0,0,0,0]
    # Load the disk images into a memory mapped variable
    rc , drive0Data = msxdos_inihrd(getMSXPiVar('DriveA'))
    rc , drive1Data = msxdos_inihrd(getMSXPiVar('DriveB'))

def dskiords(parms = None):
    print("dskiords()")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data,SECTORSIZE
    if not msxdos1boot:
        dskioini()
        
    initdataindex = sectorInfo[3]*SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    #print("dskiords:deviceNumber=",sectorInfo[0])
    #print("dskiords:numsectors=",sectorInfo[1])
    #print("dskiords:mediaDescriptor=",sectorInfo[2])
    #print("dskiords:initialSector=",sectorInfo[3])
    #print("dskiords:blocksize=",SECTORSIZE)
    
    while sectorcnt < numsectors:
        #print("dskiords:",sectorcnt)
        if sectorInfo[0] == 0:
            buf = drive0Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)]
        else:
            buf = drive1Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)]

        rc = sendmultiblock(buf)
        sectorcnt += 1
        
        if  rc == RC_SUCCESS:
            pass
            #print("dskiords: checksum is a match")
        else:
            print("dskiords: checksum error")
            break
 
def dskiowrs(parms = None):
    print("dskiowrs()")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data,SECTORSIZE
    if not msxdos1boot:
        dskioini()
        
    initdataindex = sectorInfo[3]*SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    #print("dskiowrs:deviceNumber=",sectorInfo[0])
    #print("dskiowrs:numsectors=",sectorInfo[1])
    #print("dskiowrs:mediaDescriptor=",sectorInfo[2])
    #print("dskiowrs:initialSector=",sectorInfo[3])
    #print("dskiowrs:blocksize=",SECTORSIZE)
    
    while sectorcnt < numsectors:
        rc,buf = recvdata2()
        if  rc == RC_SUCCESS:
            #print("dskiowrs: checksum is a match")
            if sectorInfo[0] == 0:
                drive0Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = buf
            else:
                drive1Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = buf
            sectorcnt += 1
        else:
            print("dskiowrs: checksum error")
            break
                  
def dskiosct(parms = None):
    print("dskiosct()")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data,SECTORSIZE
    if not msxdos1boot:
        dskioini()
  
    rc,buf = recvdata2(5)
    sectorInfo[0] = buf[0]
    sectorInfo[1] = buf[1]
    sectorInfo[2] = buf[2]
    byte_lsb = buf[3]
    byte_msb = buf[4]
    sectorInfo[3] = byte_lsb + 256 * byte_msb
    if  rc == RC_SUCCESS:
        pass
    #    print("dskiosct: checksum is a match")
    else:
        print("dskiosct: checksum error")
          
    #print("dskiosct:deviceNumber=",sectorInfo[0])
    #print("dskiosct:numsectors=",sectorInfo[1])
    #print("dskiosct:mediaDescriptor=",sectorInfo[2])
    #print("dskiosct:initialSector=",sectorInfo[3])
       
def recvdata2(maxbufsize = 8192):
    """
    Python-side counterpart of MSX SENDDATA2().
    Full block-based, multi-block protocol using SPI_ByteTransfer.

    Returns: (rc, payload_bytes) where:
      - rc is RC_SUCCESS or an error code
      - payload_bytes is bytes on success, or None on error
    """

    data = bytearray()
    expected_block_index = 0

    # -------------------------
    # 1. Initial handshake
    # MSX   -> READY
    # Python-> READY_ACK
    # MSX   -> msxmaxbuf_low, msxmaxbuf_high
    # -------------------------
    while True:
        rc, pibyte = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            continue  # ignore transient SPI errors

        if pibyte == READY:
            # Send READY_ACK back
            SPI_ByteTransfer(READY_ACK)
            break
        else:
            # Ignore garbage and keep waiting for READY
            continue

    # Receive msxmaxbuf (MSX advertised max bytes per block)
    rc, low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)
    rc, high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    msxmaxbuf = low | (high << 8)
    block_max = min(msxmaxbuf, maxbufsize)

    # -------------------------
    # 2. Block receive loop
    # -------------------------
    while True:
        # --- header_rc ---
        rc, header_rc = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # --- length low/high ---
        rc, size_low = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)
        rc, size_high = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        length = size_low | (size_high << 8)

        # --- block_index ---
        rc, block_index = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # Validate block index
        if block_index != expected_block_index:
            # Protocol drift
            return (RC_CONNERR, None)

        # Capacity checks
        if length > block_max:
            # MSX tried to send more than negotiated / allowed
            return (RC_CONNERR, None)
        if len(data) + length > maxbufsize:
            # Would overflow caller's max buffer
            return (RC_CONNERR, None)

        # --- Payload ---
        payload = bytearray(length)
        chksum = 0
        for i in range(length):
            rc, byte = SPI_ByteTransfer()
            if rc != RC_SUCCESS:
                return (RC_CONNERR, None)
            payload[i] = byte
            chksum += byte

        # --- Local checksum (Python receiver) ---
        right = chksum & 0xFF
        left  = (chksum >> 8) & 0xFF
        local_sum = (right + left) & 0xFF

        # --- Receive MSX checksum ---
        rc, msxsum = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # --- Send local checksum back ---
        SPI_ByteTransfer(local_sum)

        # --- Compare checksums ---
        if msxsum != local_sum:
            # Checksum mismatch:
            # - DO NOT commit payload
            # - DO NOT advance expected_block_index
            # - DO NOT do status handshake
            # MSX will detect mismatch and resend this block.
            continue

        # Checksums match: commit block
        data.extend(payload)
        expected_block_index += 1

        # -------------------------
        # 3. Status handshake after GOOD block
        #
        #   Python -> READY
        #   Python -> status_for_next (RC_SUCCESS / error)
        #   MSX    -> READY_ACK
        # -------------------------

        status_for_next = RC_SUCCESS  # for now, always success

        # Send READY (ignore returned byte)
        SPI_ByteTransfer(READY)

        # Send status_for_next (ignore returned byte)
        SPI_ByteTransfer(status_for_next)

        # Expect READY_ACK from MSX
        rc, ack = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_HANDSHAKEERR, None)
        if ack != READY_ACK:
            return (RC_HANDSHAKEERR, None)

        # If this was the last block, we're done
        if header_rc == RC_SUCCESS:
            return (RC_SUCCESS, bytes(data))

        # Otherwise header_rc == RC_READY: loop for next block

def senddata(header_rc, payload):
    """
    Python-side counterpart of MSX RECVDATA2().

    Protocol (final design):

      Initial handshake (before first block):
        MSX   -> READY
        Python-> READY_ACK
        MSX   -> msxmaxbuf_low, msxmaxbuf_high   (max payload bytes per block)

      For each block (block_index = 0..255, wraps):
        Python sends:
          [header_rc]    RC_READY / RC_SUCCESS / RC_CHKSUM_ERR
          [size_low]
          [size_high]
          [block_index]  (same on retries)
          [payload bytes...]
          [checksum]     (collapsed checksum of payload bytes only)

        MSX sends:
          [checksum]     (its own computed checksum for this block)

        Python:
          - If local checksum != MSX checksum:
              Retry same block up to GLOBALRETRIES,
              with header_rc = RC_CHKSUM_ERR on retries.
              If still failing -> return RC_CHKSUM_ERR.

          - If checksums match:
              Wait for status handshake about this block:

                MSX   -> READY
                MSX   -> status_byte (RC_SUCCESS / RC_CHKSUM_ERR)
                Python-> READY_ACK

              If status_byte == RC_CHKSUM_ERR:
                  MSX rejected the block, resend same block (same index, same data).
              If status_byte == RC_SUCCESS:
                  Commit block: advance offset and block_index.

      Termination:
        When all payload bytes are committed (offset >= total_size)
        and last status from MSX was RC_SUCCESS:
          -> return RC_SUCCESS

      Return codes:
        RC_SUCCESS    - All blocks sent and acknowledged by MSX.
        RC_CHKSUM_ERR - Unrecoverable checksum failure after retries.
        RC_FAILED     - SPI/protocol failure (unexpected byte, transfer error, etc.).

      Notes:
        - 'header_rc' parameter is kept for API compatibility but is NOT used.
          The function decides header_rc per block as:
            RC_READY      when more blocks will follow,
            RC_SUCCESS    when this is the last block (on first attempt),
            RC_CHKSUM_ERR on Python-side retries.
    """

    total_size = len(payload)
    offset = 0
    block_index = 0  # 0..255, wraps

    # -------------------------
    # Helper: compute collapsed checksum of a bytes-like block
    # -------------------------
    def compute_checksum(block_bytes):
        s = 0
        for b in block_bytes:
            if not isinstance(b, int):
                b = ord(b)
            s += b
        right = s & 0xFF
        left = (s >> 8) & 0xFF
        return (right + left) & 0xFF

    # -------------------------
    # Helper: wait for MSX READY + status, then ACK
    # Used after each successfully transmitted block
    # -------------------------
    def wait_status_handshake():
        """
        Waits for:
          MSX -> READY
          MSX -> status_byte  (RC_SUCCESS / RC_CHKSUM_ERR)
        Sends:
          Python -> READY_ACK

        Returns:
          (RC_SUCCESS, status_byte) on success
          (RC_FAILED, None)        on SPI/protocol failure
        """
        # Wait for READY
        while True:
            rc, b = SPI_ByteTransfer()
            if rc != RC_SUCCESS:
                # SPI error: keep waiting; higher-level timeout policy is outside this function
                continue
            if b == READY:
                break
            print(f"Status handshake: expected READY, got {b}")

        # Read status byte
        rc, status = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            print("Status handshake: failed to read status byte from MSX")
            return (RC_FAILED, None)

        # Send READY_ACK
        SPI_ByteTransfer(READY_ACK)
        print(f"Status handshake: MSX status={status}")
        return (RC_SUCCESS, status)

    # -------------------------
    # 1. Initial handshake
    # -------------------------
    while True:
        rc, pibyte = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            # SPI error: ignore and keep waiting
            continue
        if pibyte == READY:
            print("Handshake: Detected READY from MSX (initial)")
            SPI_ByteTransfer(READY_ACK)
            print("Handshake: Sent READY_ACK to MSX (initial)")
            break
        print(f"Handshake: expected READY, got {pibyte}")

    # Receive msxmaxbuf (maximum payload bytes per block)
    rc, msxmaxbuf_low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        print("senddata: failed to read msxmaxbuf_low")
        return RC_FAILED

    rc, msxmaxbuf_high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        print("senddata: failed to read msxmaxbuf_high")
        return RC_FAILED

    msxmaxbuf = msxmaxbuf_low | (msxmaxbuf_high << 8)
    print(f"senddata: MSX max payload size per block = {msxmaxbuf}")

    # -------------------------
    # 2. Block send loop
    # -------------------------
    while True:
        # All data committed?
        if offset >= total_size:
            print("senddata: all blocks committed, transfer complete")
            return RC_SUCCESS

        # Build block from current offset
        remaining = total_size - offset
        block_size = msxmaxbuf if remaining > msxmaxbuf else remaining
        block_bytes = payload[offset:offset + block_size]
        local_sum = compute_checksum(block_bytes)

        is_last_block = (offset + block_size >= total_size)
        # First attempt header: RC_SUCCESS if last, else RC_READY
        base_header = RC_SUCCESS if is_last_block else RC_READY

        print(
            f"senddata: preparing block index={block_index}, "
            f"offset={offset}, size={block_size}, checksum={local_sum}, "
            f"is_last_block={is_last_block}"
        )

        # 2a. Send this block with Python-side checksum retries
        retries = 0
        while True:
            # On retries (Python-side checksum mismatch), use RC_CHKSUM_ERR
            header_for_this_try = base_header if retries == 0 else RC_CHKSUM_ERR

            # --- Send header_rc ---
            rc, _ = SPI_ByteTransfer(header_for_this_try & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending header_rc")
                return RC_FAILED

            # --- Send size (low, high) ---
            rc, _ = SPI_ByteTransfer(block_size & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending size_low")
                return RC_FAILED

            rc, _ = SPI_ByteTransfer((block_size >> 8) & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending size_high")
                return RC_FAILED

            # --- Send block index (1 byte, wraps naturally) ---
            rc, _ = SPI_ByteTransfer(block_index & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending block_index")
                return RC_FAILED

            # --- Send payload bytes ---
            for b in block_bytes:
                if not isinstance(b, int):
                    b = ord(b)
                rc, _ = SPI_ByteTransfer(b & 0xFF)
                if rc != RC_SUCCESS:
                    print("senddata: SPI error while sending payload byte")
                    return RC_FAILED

            # --- Send checksum ---
            rc, _ = SPI_ByteTransfer(local_sum & 0xFF)
            if rc != RC_SUCCESS:
                print("senddata: SPI error while sending checksum")
                return RC_FAILED

            print(
                f"senddata: sent block index={block_index}, size={block_size}, "
                f"header_rc={header_for_this_try}, checksum={local_sum}"
            )

            # --- Receive MSX checksum for this block ---
            rc, msxsum = SPI_ByteTransfer()
            if rc != RC_SUCCESS:
                print("senddata: failed to receive checksum from MSX")
                return RC_FAILED

            print(f"senddata: received MSX checksum={msxsum}")

            if msxsum == local_sum:
                print("senddata: local/MSX checksum match (Python-side OK)")
                # Python is satisfied; MSX will confirm via status handshake.
                break

            print("senddata: checksum mismatch (Python-side), will retry block")
            retries += 1
            if retries >= GLOBALRETRIES:
                print("senddata: too many checksum retries, aborting")
                return RC_CHKSUM_ERR
            # Loop again: re-send same block with header_rc=RC_CHKSUM_ERR

        # 2b. Wait for MSX status handshake about this block
        rc, status = wait_status_handshake()
        if rc != RC_SUCCESS:
            return RC_FAILED

        if status == RC_CHKSUM_ERR:
            # MSX rejected this block; resend exact same block.
            print(
                f"senddata: MSX reported checksum error for block index={block_index}, "
                "will resend same block"
            )
            # Do NOT advance offset or block_index.
            # Loop will rebuild same block from same offset.
            continue

        if status == RC_SUCCESS:
            # MSX accepted this block; commit it.
            print(
                f"senddata: MSX accepted block index={block_index}, "
                f"committing size={block_size}"
            )
            offset += block_size
            block_index = (block_index + 1) & 0xFF
            # Loop back: if more data remains, build next block.
            continue

        print(f"senddata: unexpected MSX status={status}, aborting")
        return RC_FAILED

    MAX_BLOCK_RETRIES = 3

def recvdata2_oneblock(maxbufsize):
    """
    Python counterpart of RECVDATA2_ONEBLOCK().
    Reads exactly ONE block sent by MSX.

    Returns: (rc, payload_bytes)
      rc = RC_SUCCESS  → last block
      rc = RC_READY    → more blocks will follow
      rc = RC_CHKSUM_ERR → checksum mismatch after retries
      rc = RC_CONNERR / RC_HANDSHAKEERR → protocol failure
    """

    # -------------------------
    # 1. Initial handshake
    # MSX -> READY
    # Python -> READY_ACK
    # MSX -> msxmaxbuf_low, msxmaxbuf_high
    # -------------------------

    while True:
        rc, byte = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            continue  # ignore transient SPI noise

        if byte == READY:
            SPI_ByteTransfer(READY_ACK)
            break
        # ignore garbage and continue waiting

    # Receive msxmaxbuf
    rc, low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    rc, high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    msxmaxbuf = low | (high << 8)
    block_max = min(msxmaxbuf, maxbufsize)

    # -------------------------
    # 2. Read exactly one block
    # -------------------------

    # --- header_rc ---
    rc, header_rc = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    # --- length low/high ---
    rc, lo = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    rc, hi = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    length = lo | (hi << 8)

    if length > block_max:
        return (RC_BUFOVFLW, None)

    # --- block_index ---
    rc, block_index = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)

    # For one-block variant, MSX enforces index = 0
    if block_index != 0:
        return (RC_CONNERR, None)

    # --- Payload + checksum with retries ---
    attempts = 0

    while True:
        payload = bytearray(length)
        chksum = 0

        # Read payload
        for i in range(length):
            rc, b = SPI_ByteTransfer()
            if rc != RC_SUCCESS:
                return (RC_CONNERR, None)
            payload[i] = b
            chksum += b

        # Local checksum
        right = chksum & 0xFF
        left  = (chksum >> 8) & 0xFF
        local_sum = (right + left) & 0xFF

        # Receive MSX checksum
        rc, msxsum = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return (RC_CONNERR, None)

        # Send our checksum back
        SPI_ByteTransfer(local_sum)

        if msxsum == local_sum:
            # Block accepted
            break

        attempts += 1
        if attempts >= MAX_BLOCK_RETRIES:
            return (RC_CHKSUM_ERR, None)

        # Otherwise MSX will resend the same block; loop again

    # -------------------------
    # 3. Status handshake after GOOD block
    #
    # MSX -> READY
    # MSX -> status_for_next
    # Python -> READY_ACK
    # -------------------------

    rc, ready = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_HANDSHAKEERR, None)
    if ready != READY:
        return (RC_HANDSHAKEERR, None)

    rc, status_from_msx = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return (RC_CONNERR, None)
    if status_from_msx != RC_SUCCESS:
        return (RC_CONNERR, None)

    # Send READY_ACK
    SPI_ByteTransfer(READY_ACK)

    # -------------------------
    # 4. Interpret header_rc
    # -------------------------

    if header_rc == RC_SUCCESS:
        return (RC_SUCCESS, bytes(payload))   # last block

    if header_rc == RC_READY:
        return (RC_READY, bytes(payload))     # more blocks coming

    return (RC_CONNERR, None)                 # unexpected header

def senddata_oneblock(payload: bytes, msx_blocksize: int, header_rc: int, block_index: int = 0) -> int:
    print(f"senddata_oneblock()") #"Sending block {block_index}, header_rc={hex(header_rc)}, length={msx_blocksize}")
    length = len(payload)
    if length > msx_blocksize:
        return RC_INVALIDDATASIZE

    # 1. Initial handshake: MSX -> READY, Python -> READY_ACK
    # Is performed by sendmultiblock() once before calling this function.
    
    # 2. Send exactly one block with retries
    attempts = 0
    print("senddata_oneblock(): Sending block data with retries if needed")
    while True:
        # header_rc
        print(f"senddata_oneblock(): Sending header_rc={hex(header_rc)}")
        rc, _ = SPI_ByteTransfer(header_rc)
        if rc != RC_SUCCESS:
            return RC_CONNERR

        # length low/high
        rc, _ = SPI_ByteTransfer(length & 0xFF)
        if rc != RC_SUCCESS:
            return RC_CONNERR
        rc, _ = SPI_ByteTransfer((length >> 8) & 0xFF)
        if rc != RC_SUCCESS:
            return RC_CONNERR

        # block_index
        rc, _ = SPI_ByteTransfer(block_index & 0xFF)
        if rc != RC_SUCCESS:
            return RC_CONNERR

        # payload
        chksum = 0
        for b in payload:
            rc, _ = SPI_ByteTransfer(b)
            if rc != RC_SUCCESS:
                return RC_CONNERR
            chksum += b

        # local checksum
        right = chksum & 0xFF
        left  = (chksum >> 8) & 0xFF
        local_sum = (right + left) & 0xFF

        # send checksum
        rc, _ = SPI_ByteTransfer(local_sum)
        if rc != RC_SUCCESS:
            return RC_CONNERR

        # receive MSX checksum
        rc, msxsum = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            return RC_CONNERR

        print(f"senddata_oneblock(): local checksum={local_sum}, MSX checksum={msxsum}")
        if msxsum == local_sum:
            # block accepted
            break

        attempts += 1
        if attempts >= MAX_BLOCK_RETRIES:
            return RC_CHKSUM_ERR
        # else: loop and resend entire block

    # 3. Status handshake after GOOD block
    # MSX (receiver) does: READY, status_for_next, expects READY_ACK.
    # Python (sender) must: read READY, read status, send READY_ACK.
    print("senddata_oneblock(): Performing status handshake")
    rc, ready = SPI_ByteTransfer()
    print(f"senddata_oneblock(): MSX Handshake = {ready}")
    if rc != RC_SUCCESS:
        return RC_HANDSHAKEERR
    if ready != READY:
        return RC_HANDSHAKEERR

    rc, status_from_msx = SPI_ByteTransfer()
    print(f"senddata_oneblock(): MSX Status = {status_from_msx}")
    if rc != RC_SUCCESS:
        return RC_CONNERR
    if status_from_msx != RC_SUCCESS:
        return RC_CONNERR

    # send READY_ACK
    print("senddata_oneblock(): Sending READY_ACK to MSX")
    SPI_ByteTransfer(READY_ACK)

    # 4. Interpret header_rc (what we told MSX)
    if header_rc == RC_SUCCESS:
        return RC_SUCCESS   # last block
    if header_rc == RC_READY:
        return RC_READY     # more blocks follow
    return RC_CONNERR       # unexpected header


def PerformHandshake():
    # 1. Initial handshake: MSX -> READY, Python -> READY_ACK
    #print("PerformHandshake(): Waiting for READY from MSX")
    while True:
        rc, byte = SPI_ByteTransfer()
        if rc != RC_SUCCESS:
            continue  # ignore noise
        if byte == READY:
            SPI_ByteTransfer(READY_ACK)
            break

    # Receive msx_blocksize
    print("PerformHandshake(): Receiving msx_blocksize from MSX")
    rc, low = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_CONNERR, 0
    rc, high = SPI_ByteTransfer()
    if rc != RC_SUCCESS:
        return RC_CONNERR, 0

    msx_blocksize = low | (high << 8)

    return RC_SUCCESS, msx_blocksize

def sendmultiblock(payload: bytes):
    """
    Sends a large payload to the MSX in multiple blocks using senddata_oneblock().

    Returns:
      RC_SUCCESS  → all blocks sent, last block acknowledged
      RC_CONNERR / RC_HANDSHAKEERR / RC_CHKSUM_ERR → protocol failure
    """

    print("sendmultiblock()")
    total_len = len(payload)
    if total_len == 0:
        return RC_INVALIDDATASIZE  # or RC_SUCCESS if you want to allow empty transfers

    # Perform handshake for each block
    # Moved here to allow dynamic msx_blocksize per block,
    # Set by MSX each time.
    rc, msx_blocksize = PerformHandshake()
    if rc != RC_SUCCESS:
        return rc

    offset = 0
    block_index = 0
    while offset < total_len:

        # Determine slice for this block
        end = min(offset + msx_blocksize, total_len)
        block = payload[offset:end]

        # header_rc: RC_READY for intermediate blocks, RC_SUCCESS for last block
        if end < total_len:
            header = RC_READY
        else:
            header = RC_SUCCESS

        # Send one block
        print(f"sendmultiblock(): Sending block {block_index}, header={header}, length={len(block)}")
        rc = senddata_oneblock(block, msx_blocksize, header, block_index)
        if rc not in (RC_SUCCESS, RC_READY):
            # Any error aborts the whole transfer
            return rc

        # Advance to next block
        offset = end
        block_index += 1

    return RC_SUCCESS

def readParameters(errorMsg, needParm=False):
    print("readparms():")
    rc, data = recvdata2()

    if rc != RC_SUCCESS:
        print(f"Pi:Error reading parameters")
        encodederrorMsg = ('Pi:Error reading parameters').encode()
        sendmultiblock(encodederrorMsg)
        return RC_FAILED, None

    parms = data.decode().split("\x00")[0].strip()
    if needParm and not parms:
        print(f"Pi:Error - {errorMsg}")
        encodederrorMsg = ('Pi:Error - ' + errorMsg).encode()
        sendmultiblock(encodederrorMsg)
        return RC_FAILED, None

    #print(f"Parameters:{parms}")
    return RC_SUCCESS, parms

def restart():
    print("prestart()")
    if hostType == "RaspberryPi":
        print("Restarting MSXPi Server")
        exitDueToSyncError()
    else:
        print("Command not supported in this platform")
        
def reboot():
    print("preboot()")
    if hostType == "RaspberryPi":
        print("Rebooting Raspberry Pi")
        os.system("sudo reboot")
    else:
        print("Command not supported in this platform")
        
def shut():
    print("pshut()")
    if hostType == "RaspberryPi":
        print("Shutting down Raspberry Pi")
        os.system("sudo shutdown -h now")
    else:
        print("Command not supported in this platform")

def button_handler(channel):
    start = time.time()
    # Wait for release
    while GPIO.input(RPI_SHUTDOWN) == GPIO.LOW:
        time.sleep(0.01)
    duration = time.time() - start

    if duration >= 3:
        print("Shutdown triggered")
        os.system("sudo shutdown -h now")
    else:
        print("Reboot triggered")
        os.system("sudo reboot")

   
def exitDueToSyncError():
    print("Sync error. Recycling MSXPi-Server")
    GPIO.cleanup() # cleanup all GPIO
    os.system("/home/pi/msxpi/kill.sh")

def updateIniFile(fname,memvar):
    f = open(fname, 'w')
    for v in memvar:
        f.writelines('var '+v[0]+'='+v[1]+'\n')
    f.close()
    
def chatgpt(query):
    print("chatgpt()")
    print(query)
    api_key = getMSXPiVar('OPENAIKEY')
    if not api_key or api_key == "Your OpenAI API Key":
        print('Pi:Error - OPENAIKEY is not defined. Define your key with PSET or add to msxpi.ini')
        sendmultiblock(b'Pi:Error - OPENAIKEY is not defined. Define your key with PSET or add to msxpi.ini')
        return RC_FAILED

    model_engine = "gpt-3.5-turbo"
    url = "https://api.openai.com/v1/chat/completions"

    try:
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "model": model_engine,
            "messages": [
                {"role": "user", "content": query}
            ]
        }
        
        response = requests.post(url, headers=headers, json=payload)
        openai_response = response.json()
        if "choices" in openai_response:
            response_text = openai_response["choices"][0]["message"]["content"]
            sendmultiblock(response_text.encode())
        else:
            sendmultiblock(openai_response.encode())
    except Exception as e:
        error_msg = f"Pi:Error - {str(e)}"
        print(error_msg)
        sendmultiblock(error_msg.encode())

def fetch_and_uncompress(url: str):
    """
    Download a compressed file from URL into /tmp/msxpi (cache).
    Detect compression type by extension and uncompress.
    Return (rc, buf) where rc is RC_SUCCESS or RC_FAILED,
    and buf is the resulting .rom file contents as bytes.
    """
    tmpdir = "/tmp/msxpi"
    os.makedirs(tmpdir, exist_ok=True)

    filename = os.path.basename(url)
    cached_path = os.path.join(tmpdir, filename)

    # Download only if not cached
    if not os.path.exists(cached_path):
        try:
            resp = requests.get(url, stream=True)
            resp.raise_for_status()
            with open(cached_path, "wb") as f:
                for chunk in resp.iter_content(chunk_size=8192):
                    f.write(chunk)
        except Exception as e:
            print(f"Download failed: {e}")
            return RC_FAILED, f"Download failed: {e}"
    else:
        print(f"Using cached file: {cached_path}")

    # Handle plain .rom files directly
    ext = filename.lower().split(".")[-1]
    if ext == "rom":
        try:
            with open(cached_path, "rb") as f:
                buf = f.read()
            return RC_SUCCESS, buf
        except Exception as e:
            print(f"Failed to read ROM file: {e}")
            return RC_FAILED, f"Failed to read ROM file: {e}"

    # Otherwise, prepare extraction
    extract_dir = os.path.join(tmpdir, "extract")
    if os.path.exists(extract_dir):
        shutil.rmtree(extract_dir)
    os.makedirs(extract_dir)

    system = platform.system().lower()

    if ext == "zip":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["unzip", "-o", cached_path, "-d", extract_dir]

    elif ext == "lzh":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["lha", "xq", cached_path, extract_dir]

    elif ext == "pma":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["pma", "x", cached_path, extract_dir]

    elif ext == "arj":
        if system == "windows":
            cmd = ["7z.exe", "e", cached_path, "-aoa", f"-o{extract_dir}"]
        else:
            cmd = ["arj", "x", cached_path, extract_dir]

    else:
        print(f"Unsupported extension: {ext}")
        return RC_FAILED, f"Unsupported extension: {ext}"

    # Run extraction
    try:
        subprocess.run(cmd, check=True)
    except subprocess.CalledProcessError as e:
        print(f"Extraction failed: {e}")
        return RC_FAILED, f"Extraction failed: {e}"

    # Find the resulting .rom file
    rom_file = None
    for root, _, files in os.walk(extract_dir):
        for f in files:
            if f.lower().endswith(".rom"):
                rom_file = os.path.join(root, f)
                break
        if rom_file:
            break

    if not rom_file:
        print("No .rom file found after extraction")
        shutil.rmtree(extract_dir)
        return RC_FAILED, "No .rom file found after extraction"

    # Load into buf
    try:
        with open(rom_file, "rb") as f:
            buf = f.read()
    except Exception as e:
        print(f"Failed to read ROM file: {e}")
        shutil.rmtree(extract_dir)
        return RC_FAILED, f"Failed to read ROM file: {e}"

    # Clean up extracted files, keep cache
    shutil.rmtree(extract_dir)

    return RC_SUCCESS, buf

def msxarchive(parms = None):
    stored_screen = ""  # local variable inside ploadr
    nrows = 22
    ncolumns = 80
    columnwidth = 14
    indexFile = "00index.txt"

    def fetch_file_list(url: str, index: str):
        """Fetch file list from the given URL and return filenames without extensions.
        Skip header (first line) and empty lines."""

        url = url + "/" + index
        cached_file = "/tmp/msxpi/" + url.replace(":", "_").replace("/", "+")
        
        if not os.path.exists(cached_file):
            print(f"not cached: {cached_file}")
            # Download from the URL
            response = requests.get(url)

            if response.status_code == 200:
                # Success: parse the content
                lines = response.text.splitlines()
            else:
                # Failure: print error message
                print(f"Download failed: HTTP {response.status_code} - {response.reason}")
                files = f"Download failed: HTTP {response.status_code} - {response.reason}"
                return RC_FAILED,files

            lines = response.text.splitlines()

            # Save to cache for future use
            os.makedirs(os.path.dirname(cached_file), exist_ok=True)
            with open(cached_file, "w", encoding="utf-8") as f:
                f.write(response.text)
        
        else:
            # Read from cache
            print(f"Reading from cache: {url}")
            with open(cached_file, "r", encoding="utf-8") as f:
                lines = f.read().splitlines()

        files = []
        for i, line in enumerate(lines):
            line = line.strip()
            if i == 0 or not line or line.startswith('#'):  # skip header + empty + comments
                continue
            # Drop extension
            name = line.split(' ')[0]
            files.append(name)
        return RC_SUCCESS,files

    def paginate_files(files, rows=nrows, cols=ncolumns, col_width=None):
        """
        Arrange files into pages of rows x cols with horizontal indexing.
        Column width is determined by the longest filename (plus index prefix),
        unless explicitly provided. Pads the last page with spaces so all pages
        have equal size. Ensures a space between columns.
        """
        if not files:
            return []

        # Compute max column width if not provided
        if col_width is None:
            max_name_len = max(len(f) for f in files)
            max_index_len = len(str(len(files)))  # e.g. "650" → 3
            col_width = max_name_len + max_index_len + 1  # +1 for colon

        # Clamp column width to avoid overflow
        if col_width > cols:
            col_width = cols

        # Ensure at least one column
        cols_count = max(1, cols // (col_width + 1))  # +1 for spacing
        items_per_page = cols_count * rows
        total_pages = max(1, math.ceil(len(files) / items_per_page))

        # Truncate filenames and add index
        files = [f[:col_width] for f in files]
        indexed = [f"{i+1}:{name}" for i, name in enumerate(files)]

        pages = []
        for p in range(total_pages):
            start = p * items_per_page
            end = start + items_per_page
            chunk = indexed[start:end]

            # Pad chunk to fill the page
            while len(chunk) < items_per_page:
                chunk.append("".ljust(col_width))

            page_lines = []
            for r in range(rows):
                row_items = []
                for c in range(cols_count):
                    idx = r * cols_count + c
                    # Add one space after each column
                    row_items.append(chunk[idx].ljust(col_width) + " ")
                # Trim to exactly 'cols' width
                page_lines.append("".join(row_items)[:cols].ljust(cols))
            pages.append(page_lines)

        return pages

    def get_page(files, pages, page_number, width=ncolumns):
        """
        Return only the requested page as plain text, update stored_screen.
        Each line is padded with spaces to 'width' and concatenated without newlines.
        """
        nonlocal stored_screen  # use nonlocal to modify outer variable
        total_pages = len(pages)
        if 1 <= page_number <= total_pages:
            lines = pages[page_number - 1]
        else:
            lines = []
    
        # Pad each line to the full width with spaces
        padded_lines = [line.ljust(width) for line in lines]
    
        # Concatenate into one continuous string (no '\n')
        stored_screen = "".join(padded_lines)
        return stored_screen

    def get_total_files(files):
        """Return the total number of files."""
        return len(files)
    
    def get_total_pages(pages):
        """Return the total number of pages."""
        return len(pages)
    
    def get_fileName(files, index):
        """
        Return the filename at the given 1-based index.
        If the index is out of range, return None.
        """
        if 1 <= index <= len(files):
            return files[index - 1]   # convert from 1-based to 0-based
        else:
            return None

    # This command requires parameter
    rc, url = readParameters("This command requires a parameter", True)
    if rc == RC_FAILED:
        return RC_FAILED

    PAGESIZE = nrows * ncolumns

    print(f"Fetching MSX Archive file list from: {url + '/'  + indexFile}")    
    rc, files = fetch_file_list(url, indexFile)

    if rc == RC_FAILED:
        senddata(RC_FAILED, files.encode().ljust(PAGESIZE, b'\x00'))
        return RC_FAILED

    pages = paginate_files(files, nrows, ncolumns, None)

    print(f"total files = {get_total_files(files)}, total pages = {get_total_pages(pages)}")
    #text = get_page(files, pages, 1)
    #print(text)
    #print("")

    page = 1
    current_page = 1
    global DISABLETIMEOUT
    DISABLETIMEOUT = True # Disable transfers timeout for MSX Archive browsing
    cmd = "1"
    text = get_page(files, pages, page, ncolumns)
    rc = senddata(RC_SUCCESS, text.encode().ljust(PAGESIZE, b'\x00'))
    print(text)
    while True:   
        rc, parm = recvdata2();
        parm = parm.decode(errors="ignore").split("\x00", 1)[0]
        cmd = str(parm).lower()  # normalize to string for command checks

        if cmd == "n" or cmd == "N":
            # go to next page
            page = int(current_page) + 1
            if page > get_total_pages(pages):
                page = 1
    
            current_page = page
            text = get_page(files, pages, page, ncolumns)

        elif cmd == "p" or cmd == "P":
            # go to previous page
            page = int(current_page) - 1
            if page < 1:
                page = get_total_pages(pages)
            current_page = page
            text = get_page(files, pages, page, ncolumns)

        elif cmd == "q" or cmd == "Q":
            break
        else:
            try:
                file_num = int(parm)
                if file_num < 1 or file_num > get_total_files(files):
                    print(f"File {file_num} does not exist.")
                    text = f"File {file_num} does not exist."
                else:
                    filename = get_fileName(files, file_num)
                    print(f"Selected file: {filename}")
                    rc, buf = fetch_and_uncompress(f"{url}/{filename}")
                    if rc == RC_SUCCESS:
                        text = "File fetched and uncompressed successfully."
                    else:
                        text = buf
            except (ValueError, TypeError):
                print(f"Invalid input: {cmd}")
                text = f"Invalid input: {cmd}"
        
        rc = senddata(RC_SUCCESS, text.encode().ljust(PAGESIZE, b'\x00'))
        print(text)

    DISABLETIMEOUT = False # Restore timeout setting

def ShowSecurityDisclaimer(parms = None):
    print("\n=====================================================================================")
    print("This server process is meant to handle communication with a MSX computer.")
    print("It allows the MSX to:\n")
    print(" * List/read (any) file from this computer or network (via the the PDIR/PCOPY commands).\n")
    print(" * Execute arbitrary(!) shell commands (via the PRUN command).\n")
    if hostType == "RaspberryPi":
        print(" * Configure the WiFi settings (via the PSET/PWIFI commands).\n")
    print("Some very few commands designed specifically for Raspberry Pi requires elevation of")
    print("privileges using sudo - these commands will not be executed in the PC platforms and")
    print("when possible, a message will be returned to the MSX informing that the command is")
    print("not supported.")
    print("However notice that using PRUN, the MSX user can execute any commands in the host,")
    print("bypassing the controls in the native MSXPi commands.")
    print("=======================================================================================\n")   

def template(parms = None):

    # This method is a template for new commands
    # 
    print("template()")

    # If your MSX command send parameters, we go read them:
    #rc, parms = readParameters("This command requires a parameter", True)
    
    print("Parameters received:", parms)

    # parms is a bytes object
    #parmstring = parms.split(b'\x00', 1)[0].decode('ascii')
    print(f"Parameters received: {parms}")

    response = f"Response from MSXPi: I received parameter '{parms}'"
    print(f"Sending back: {response}")

    if len(response) > BLKSIZE:
        # if longer than BLKSIZE, use multiblock
        # No need to pad - sendmultiblock handles it
        rc = sendmultiblock(response.encode())
    else:
        # Because this is text, we pad with nulls to avoid garbage at the end
        padded = response.encode().ljust(BLKSIZE, b'\x00')
        rc = sendmultiblock(padded)
    
    return

def initialize_connection():
    if hostType == "RaspberryPi":
        init_spi_bitbang()
        GPIO.output(RPI_READY, GPIO.HIGH)
        time.sleep(0.2)
        GPIO.output(RPI_READY, GPIO.LOW)

        GPIO.add_event_detect(RPI_SHUTDOWN, GPIO.FALLING, callback=button_handler, bouncetime=200)
        print(f"[MSXPi Server on {hostType}] Listening on GPIOs:\n"
              f" ** CS={SPI_CS}, CLK={SPI_SCLK}, MOSI={SPI_MOSI}, MISO={SPI_MISO}, PI_READY={RPI_READY} **\n")
        return None
    else:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((HOST, PORT))
        s.listen(1)
        print(f"[MSXPi Server on {hostType}] Listening on {HOST}:{PORT}...")
        return s

""" ============================================================================
    MSXPi Server (msxpi-server.py) main program starts here
    ============================================================================
"""

# This section reads the persistent user configuration from msxpi.ini configuration file.
# When msxpi.ini does not exist, it populates the memory variables with default values.
if exists(MSXPIHOME+'/msxpi.ini'):
    f = open(MSXPIHOME+'/msxpi.ini','r')
    idx = 0
    psetvar = []
    while True:
        line = f.readline()
        if not line:
            break
    
        if line.startswith('var'):
            var = line.split(' ')[1].split('=')[0].strip()
            value = line.replace('var ','',1).replace(var,'',1).split('=')[1].strip()
            psetvar.append([var,value])
            idx += 1
    f.close()
    if 'SPI_CS' not in str(psetvar):
        psetvar.append(["SPI_HW","False"])
        psetvar.append(["SPI_CS","21"])
        psetvar.append(["SPI_SCLK","20"])
        psetvar.append(["SPI_MOSI","16"])
        psetvar.append(["SPI_MISO","12"])
        psetvar.append(["RPI_READY","25"])
    if 'free' not in str(psetvar):
        psetvar.append(["free","free"])

else:
    psetvar = [['PATH','/home/pi/msxpi'], \
           ['DriveA','/home/pi/msxpi/disks/msxpiboot.dsk'], \
           ['DriveB','/home/pi/msxpi/disks/tools.dsk'], \
           ['DriveM','https://github.com/costarc/MSXPi/raw/master/software/target'], \
           ['DriveR1','https://www.msxarchive.nl/pub/msx/games/roms/msx1'], \
           ['DriveR2','https://www.msxarchive.nl/pub/msx/games/roms/msx2'], \
           ['WIDTH','80'], \
           ['WIFISSID','MYWIFI'], \
           ['WIFIPWD','MYWFIPASSWORD'], \
           ['WIFICOUNTRY','GB'], \
           ['DSKTMPL','/home/pi/msxpi/disks/blank.dsk'], \
           ['IRCNICK','msxpi'], \
           ['IRCADDR','chat.freenode.net'], \
           ['IRCPORT','6667'], \
           ['SPI_HW','False'], \
           ['SPI_CS','21'], \
           ['SPI_SCLK','20'], \
           ['SPI_MOSI','16'], \
           ['SPI_MISO','12'], \
           ['RPI_READY','25'], \
           ['OPENAIKEY','']]

print(f"\n** Starting MSXPi Server Version {version} Build {BuildId} **\n")

# Initialize the server
hostType = detect_host()
ShowSecurityDisclaimer()

if hostType == "RaspberryPi":
    import RPi.GPIO as GPIO

# GPIO Pins is now defined by the user
SPI_CS = int(getMSXPiVar("SPI_CS"))
SPI_SCLK = int(getMSXPiVar("SPI_SCLK"))
SPI_MOSI = int(getMSXPiVar("SPI_MOSI"))
SPI_MISO = int(getMSXPiVar("SPI_MISO"))
RPI_READY = int(getMSXPiVar("RPI_READY"))

server_socket = initialize_connection()

# Start MSXPi Server main loop - wait command and execute.
# Set a interrupt for Control+C to exit the program gracefully and cleaning GPIO
# status (on Raspberry PI)
try:
    if hostType == "RaspberryPi":
        # Existing SPI main loop goes here unchanged
        while True:
            try:
                print("MSXPi Server: Waiting Command")
                DISABLETIMEOUT = True
                rc, buf = recvdata2()
                print(f"MSXPi Server: Command received: {buf} (rc={hex(rc)})")

                if rc == RC_SUCCESS:
                    DISABLETIMEOUT = False
                    buf = buf.decode()
                    cmd, *rest = buf.split()
                    parms = " ".join(rest)
                    globals()[cmd.lower()](parms)

            except Exception as e:
                errcount += 1
                print(f"MSXPi Server: {str(e)}")
                sendmultiblock(("Pi:Error - " + str(e)).encode())
                # SPI mode continues, no reconnection logic

    else:
        # TCP mode: accept loop
        while True:
            print("MSXPi Server: Waiting for MSX connection...")
            conn, addr = server_socket.accept()
            print(f" ** MSX Connected to {addr} **\n")

            # Make conn visible to recvdata2()/sendmultiblock if they rely on a global
            globals()['conn'] = conn

            try:
                while True:
                    print("MSXPi Server: Waiting Command")
                    DISABLETIMEOUT = True
                    rc, buf = recvdata2()
                    print(f"MSXPi Server: Command received: {buf} (rc={hex(rc)})")

                    if rc == RC_SUCCESS:
                        DISABLETIMEOUT = False
                        buf = buf.decode()
                        cmd, *rest = buf.split()
                        parms = " ".join(rest)
                        globals()[cmd.lower()](parms)
                    else:
                        # handle protocol-level rc if you use RC_CONNERR, etc.
                        # e.g., break on connection error
                        pass

            except (ConnectionResetError, BrokenPipeError, OSError) as e:
                print(f"MSXPi Server: connection lost: {e}")
            except Exception as e:
                errcount += 1
                print(f"MSXPi Server: {str(e)}")
                try:
                    sendmultiblock(("Pi:Error - " + str(e)).encode())
                except Exception:
                    pass  # ignore if connection is already dead
            finally:
                try:
                    conn.close()
                except Exception:
                    pass
                print("MSXPi Server: Client disconnected, waiting for new connection...")

except KeyboardInterrupt:
    if hostType == "RaspberryPi":
        GPIO.cleanup()
    try:
        if server_socket:
            server_socket.close()
    except Exception:
        pass
    print("MSXPi Server: Terminating")
