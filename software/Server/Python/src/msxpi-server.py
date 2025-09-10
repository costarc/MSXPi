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

version = "1.2"
BuildId = "20250910.790"

CMDSIZE = 3 + 9
MSGSIZE = 3 + 128
BLKSIZE = 3 + 256
SECTORSIZE = 3 + 512
BULKBLKSIZE = 3 + 4096

SPI_SCLK_LOW_TIME = 0.001
SPI_SCLK_HIGH_TIME = 0.001

GLOBALRETRIES       = 10
SPI_INT_TIME        = 3000
PIWAITTIMEOUTOTHER  = 120     # seconds
PIWAITTIMEOUTBIOS   = 60      # seconds
SYNCTIMEOUT         = 5
BYTETRANSFTIMEOUT   = 5
SYNCTRANSFTIMEOUT   = 3
STARTTRANSFER       = 0xA0
SENDNEXT            = 0xA1
ENDTRANSFER         = 0xA2
READY               = 0xAA
ABORT               = 0xAD
WAIT                = 0xAE

RC_SUCCESS          =    0xE0
RC_INVALIDCOMMAND   =    0xE1
RC_TXERROR          =    0xE2
RC_TIMEOUT          =    0xE3
RC_INVALIDDATASIZE  =    0xE4
RC_OUTOFSYNC        =    0xE5
RC_FILENOTFOUND     =    0xE6
RC_FAILED           =    0xE7
RC_CONNERR          =    0xE8
RC_WAIT             =    0xE9
RC_READY            =    0xEA
RC_SUCCNOSTD        =    0xEB
RC_FAILNOSTD        =    0xEC
RC_TERMINATE        =    0xED
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

HOST = '0.0.0.0'  # Listen on all interfaces
PORT = 5000       # Match this with serverPort in your C++ code
conn = None

hostType = "pi"

def detect_host():
    system = platform.system()
    machine = platform.machine()

    if system == "Windows":
        return "win"

    elif system == "Darwin":
        return "mac"
    elif system == "Linux":
        # Check for Raspberry Pi
        try:
            with open("/proc/cpuinfo", "r") as f:
                cpuinfo = f.read()
            if "Raspberry Pi" in cpuinfo or "BCM" in cpuinfo or "Raspberry" in platform.uname().node:
                return "pi"
        except Exception:
            pass
        return "lin"
    else:
        return system

def init_spi_bitbang():

    global SPI_CS
    global SPI_SCLK
    global SPI_MOSI
    global SPI_MISO
    global RPI_READY

# Pin Setup:
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(SPI_CS, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(SPI_SCLK, GPIO.OUT)
    GPIO.setup(SPI_MOSI, GPIO.IN)
    GPIO.setup(SPI_MISO, GPIO.OUT)
    GPIO.setup(RPI_READY, GPIO.OUT)

def tick_sclk():

    global SPI_SCLK
    GPIO.output(SPI_SCLK, GPIO.HIGH)
    time.sleep(0.00001)  # 10 µs or whatever matches your CPLD timing
    GPIO.output(SPI_SCLK, GPIO.LOW)

def SPI_MASTER_transfer_byte(byte_out=None):
    
    global conn, hostType
    byte_in = 0    
    if hostType == "pi":
        #print("SPI_MASTER_transfer_byte(): Raspberry Pi")
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
    else:
        #conn.settimeout(3.0)  # Set timeout once, e.g. during setup
        if byte_out is not None:
            # print("SPI_MASTER_transfer_byte(): Non-Raspberry Pi conn.sendall")
            conn.sendall(bytes([byte_out]))
        else:
            # print("SPI_MASTER_transfer_byte(): Non-Raspberry Pi conn.recv")
            try:
                byte_in = conn.recv(1)[0]  # Passive receive mode
            except socket.timeout:
                print("SPI_MASTER_transfer_byte(): recv timed out")
                return RC_FAILED,None

    #print(f"Received: {chr(byte_in)}")
    return RC_SUCCESS,byte_in
    
def piexchangebyte(byte_out=None):
    """
    Exchanges a byte with the MSXPi interface.
    If byte_out is provided, sends it and ignores the response.
    If byte_out is None, waits and reads a byte from MSX.
    """

    global hostType
    if hostType == "pi":
        #print("piexchange(): Raspberry Pi")
        # GPIO-based SPI emulation
        global SPI_CS, RPI_READY

        GPIO.output(RPI_READY, GPIO.HIGH)
        while GPIO.input(SPI_CS):
            #print("Waiting SPI_CS signal")
            pass

        rc, byte_in = SPI_MASTER_transfer_byte(byte_out)
        GPIO.output(RPI_READY, GPIO.LOW)
    else:
        #print("piexchange(): Non-Raspberry Pi")
        # Socket-based communication
        global conn
        rc, byte_in = SPI_MASTER_transfer_byte(byte_out)

    return rc, byte_in

# Using CRC code from :
# https://stackoverflow.com/questions/25239423/crc-ccitt-16-bit-python-manual-calculation
crc_poly = 0x1021
def crcinit(c):
    crc = 0
    c = c << 8
    for j in range(8):
        if (crc ^ c) & 0x8000:
            crc = (crc << 1) ^ crc_poly
        else:
            crc = crc << 1
        c = c << 1
    return crc

crctab = [ crcinit(i) for i in range(256) ]

def crc16(crc, c):
    cc = 0xff & c

    tmp = (crc >> 8) ^ cc
    crc = (crc << 8) ^ crctab[tmp & 0xff]
    crc = crc & 0xffff

    return crc

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
    print(f"pathExpander(): {path}, {basepath}")
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
    
    print(f"pathExpander(): urltype = {urltype}, newpath = {newpath}")
    return [urltype, newpath]

def msxdos_inihrd(filename, access=mmap.ACCESS_WRITE):
    
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

    #print(hex(rc))
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

    #print("ini_fcb: starting")
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
    
    #print("Drive, Filename, N# blocks:",msxdrive,msxfcbfname,numblocks)

    # send FCB structure to MSX
    buf = bytearray()
    buf.extend(msxdrive.to_bytes(1,'little'))
    buf.extend(msxfcbfname.encode())
    
    rc = sendmultiblock(buf, BLKSIZE, RC_SUCCESS)
    
    #print("ini_fcb: Exiting")
    
    return rc

def prun(cmd = ''):
    global hostType
    
    print(f"prun(): {cmd}")

    rc = RC_SUCCESS
    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        rc, cmd = readParameters("Syntax: prun <command> <::> command. To  pipe a command to other, use :: instead of |", True)

    if rc != RC_SUCCESS:
        return RC_FAILED
    else:
        cmd = cmd.replace('::','|')
        rc = RC_SUCCESS
        try:
            if hostType == "win":
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
            
            #print(f"prun(): output = {buf}")
            sendmultiblock(buf.encode(), BLKSIZE, rc)
            return rc
        except Exception as e:
            print("prun: exception:"+str(e))
            sendmultiblock(("Pi:Error - "+str(e)).encode(),BLKSIZE, rc)
            return rc

def pdir():
    print("pdir()")
    
    basepath = getMSXPiVar('PATH')
    rc, data = readParameters("", False)   
    if rc != RC_SUCCESS:
        return RC_FAILED
    
    if not data:
        userPath=''
    else:
        userPath = data

    pathType, path = pathExpander(userPath, basepath)
                
    try:
        if pathType == 0:
            if hostType == "win":
                prun('dir ' + path)
            else:
                prun('ls -l ' + path)
        else:
            parser = MyHTMLParser()
            htmldata = urlopen(path).read().decode()
            parser = MyHTMLParser()
            parser.feed(htmldata)
            buf = " ".join(parser.HTMLDATA)
            rc = sendmultiblock(buf.encode(),BLKSIZE, RC_SUCCESS)
    except Exception as e:
        sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_SUCCESS)

    return RC_SUCCESS

def pcd():
    print("pcd")
    
    rc = RC_SUCCESS
    basepath = getMSXPiVar('PATH')
    rc, data = readParameters("", False)   
    if rc != RC_SUCCESS:
        return RC_FAILED
    
    if not data:
        userPath=''
    else:
        userPath = data
        
    try:
        if (len(userPath) == 0 or userPath == '' or userPath.strip() == "."):
            rc = sendmultiblock(basepath.encode(), BLKSIZE, RC_SUCCESS)
        elif (userPath.strip() == ".."):
            newpath = basepath.rsplit('/', 1)[0]
            if (newpath == ''):
                newpath = '/'
            setMSXPiVar('PATH',newpath)
            rc = sendmultiblock(newpath.encode(), BLKSIZE, RC_SUCCESS)
        else:
            pathType, path = pathExpander(userPath, basepath)
            if pathType == 0:
                if (os.path.isdir(path)):
                    setMSXPiVar('PATH',path)
                    rc = sendmultiblock(path.encode(), BLKSIZE, RC_SUCCESS)
                else:
                    sendmultiblock("Pi:Error - not a folder".encode(), BLKSIZE, RC_FAILED)
            else:
                setMSXPiVar('PATH',path)
                rc = sendmultiblock(path.encode(), BLKSIZE, rc)
    except Exception as e:
        print("pcd:"+str(e))
        sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)

    return RC_SUCCESS
    
def pcopy(msxcmd = "pcopy"):

    print("pcopy():")
    
    global hostType
    rc = RC_SUCCESS

    global psetvar,GLOBALRETRIES
    basepath = getMSXPiVar('PATH')
    
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
            rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)
            return RC_FAILED
    else:
        print(f"(pcopy(): remote file = {path}")
        try:
            urlhandler = urlopen(path)
            buf = urlhandler.read()
            filesize = len(buf)
            rc = RC_SUCCESS
        except Exception as e:
            print(f"Pi:Error - {str(e)}")
            rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)
            return RC_FAILED

    # if /z passed, will uncompress the file
    if rc == RC_SUCCESS:
        if expand:
            print(f"(pcopy): Loaded, now expanding")
            tmpfn0 = path.split('/')
            tmpfn = tmpfn0[len(tmpfn0)-1]
            if hostType == "win":
                os.system('del /Q "C:\\tmp\\msxpi\\*"')
            else:
                os.system('rm /tmp/msxpi/* 2>/dev/null')
            
            tmpfile = open('/tmp/' + tmpfn, 'wb')
            tmpfile.write(buf)
            tmpfile.close()
            
            # If not windows, uses lha to extrac lzh files
            if ".lzh" in tmpfn:
                print(f"(pcopy(): hostType = {hostType}")
                if hostType == "win":
                    cmd = 'lha -xfiw=/tmp/msxpi /tmp/' + tmpfn
                else:
                    cmd = '/usr/bin/lhasa -xfiw=/tmp/msxpi /tmp/' + tmpfn
                    
                print(f"pcopy(): {cmd}")
                p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
                perror = (p.stderr.read().decode())
                rc = p.poll()
                print(f"pcopy(): perror = {perror}, rc = {rc}")
                if rc!=0 and rc != None:
                    rc = RC_FAILED
            else:
                # Will use 7-Zip for any file type under Windows
                if hostType == "win":
                    cmd = '7z.exe e /tmp/' + tmpfn + ' -aoa -o/tmp/msxpi/'
                else:
                    cmd = '/usr/bin/unar -f -o /tmp/msxpi /tmp/' + tmpfn
                p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
                perror = (p.stderr.read().decode())
                rc = p.poll()
                if rc!=0:
                    rc = RC_FAILED
            
            print(f"pcopy(): perror = {perror} , rc = {rc}")
            romfiles = [f for f in os.listdir('/tmp/msxpi') if f.endswith(('.rom', '.ROM'))]
            print(f"pcopy(): romfiles = {romfiles}")
            if romfiles:
                fname1 = '/tmp/msxpi/' + romfiles[0]
                
                try:
                    with open(fname1, mode='rb') as f:
                        buf = f.read()

                    filesize = len(buf)
                    rc = RC_SUCCESS
                    
                except Exception as e:
                    rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)
                    return RC_FAILED
       
            else:
                print(f"Pi:Error - {perror}")
                rc = sendmultiblock(('Pi:Error - ' + perror).encode(), BLKSIZE, RC_FAILED)
                return RC_FAILED
    
    # If all good so far (including eventual decompress if needed)
    # then send the file to MSX
    if rc == RC_SUCCESS:
        if filesize == 0:
            rc = sendmultiblock("Pi:Error - File size is zero bytes".encode(), BLKSIZE, RC_FAILED)
            return RC_FAILED

        else:
            print(f"(pcopy): checks before sending file")
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
                rc = sendmultiblock(buf,SECTORSIZE, rc)
            
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
                    sendmultiblock("Pi:Ok".encode(), BLKSIZE, RC_TERMINATE)
                except Exception as e:
                    rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)
            
    #print(hex(rc))
    return rc

def formatrsp(rc,lsb,msb,msg,size=BLKSIZE):
    b = bytearray(size)
    b[0] = rc
    b[1] = lsb
    b[2] = msb
    b[3:len(msg)] = bytearray(msg.encode())
    return b
    
def pdate():
    print("pdate")
    
    pdate = bytearray(8)
    now = datetime.datetime.now()
    pdate[0]=(now.year & 0xff)
    pdate[1]=(now.year >>8)
    pdate[2]=(now.month)
    pdate[3]=(now.day)
    pdate[4]=(now.hour)
    pdate[5]=(now.minute)
    pdate[6]=(now.second)
    pdate[7]=(0)
    
    sendmultiblock(pdate, CMDSIZE, RC_SUCCESS)
   
    return RC_SUCCESS
    
    # old code - never executed 
    now = datetime.datetime.now()
    piexchangebyte(now.year & 0xff)
    piexchangebyte(now.year >>8)
    piexchangebyte(now.month)
    piexchangebyte(now.day)
    piexchangebyte(now.hour)
    piexchangebyte(now.minute)
    piexchangebyte(now.second)
    piexchangebyte(0)


def pplay():
    print("pplay")   
    rc, data = readParameters("yntax:\npplay play|loop|pause|resume|stop|getids|getlids|list <filename|processid|directory|playlist|radio>\nExemple: pplay play music.mp3", True) 
    
    if rc != RC_SUCCESS:
        return RC_FAILED

    parmslist = data.split(" ")
    cmd = parmslist[0]
    if len(parmslist) > 1:
        parms = data.split(" ")[1].split("\x00")[0]
    else:
        parms = ''
    
    #print("cmd / parms:",cmd,parms)
    
    buf = ''
    try:
        buf = subprocess.check_output(['/home/pi/msxpi/pplay.sh',getMSXPiVar('PATH'),cmd,parms])
        if buf == b'':
            buf = b'\x0a'
        sendmultiblock(buf, BLKSIZE, RC_SUCCESS)
    except subprocess.CalledProcessError as e:
        sendmultiblock(("Pi:Error - "+str(e)).encode(),BLKSIZE, RC_FAILED)

    return RC_SUCCESS
    
def pvol():
    print("pvol")
    rc = RC_SUCCESS
    
    rc, data = readParameters("", False)   
    if rc != RC_SUCCESS:
        return RC_FAILED
    
    rc = prun("mixer set PCM -- " + data)
    return rc

def pset(varn = '', varv = ''):
    print("pset")
    global psetvar,drive0Data,drive1Data

    if varn == '':
        rc, data = readParameters("", False)
        if rc != RC_SUCCESS:
            return RC_FAILED
        if not data:
            for index in range(0,len(psetvar)):
                print(psetvar[index])
                data = data + psetvar[index][0]+'='+psetvar[index][1]+'\n'
            rc = sendmultiblock(data.encode(), BLKSIZE, RC_SUCCESS)
            return RC_SUCCESS
        else:
            if  (data.lower() == "/h" or data.lower() == "/help"):
                rc = sendmultiblock("Syntax:\npset                    Display variables\npset varname varvalue   Set varname to varvalue\npset varname            Delete variable     varname".encode(), BLKSIZE, RC_FAILED)
                return rc

        varname = data.split(" ")[0]
        varvalue = data.replace(varname,'',1).strip()
    else:
        varname = varn
        varvalue = varv

    rc = setMSXPiVar(varname, varvalue)
    
    if rc == RC_SUCCESS:
        if varname.upper() == 'DRIVEA':
            rc,drive0Data = msxdos_inihrd(varvalue)
            updateIniFile(MSXPIHOME+'/msxpi.ini',psetvar)
        elif varname.upper() == 'DRIVEB':
            rc,drive1Data = msxdos_inihrd(varvalue)
            updateIniFile(MSXPIHOME+'/msxpi.ini',psetvar)
        
        if varn == '':
            rc = sendmultiblock("Pi:Ok".encode(), BLKSIZE, RC_SUCCESS)
        return rc
    else:
        if varn == '':
            sendmultiblock("Pi:Error".encode(), BLKSIZE, RC_FAILED)

def setMSXPiVar(pvar = '', pvalue = ''):
    global psetvar
    
    index = 0
    for index in range(0,len(psetvar)):
        if (psetvar[index][0].upper() == pvar.upper()):
            if pvalue == '':  #will erase / clean a variable
                psetvar[index][0] = 'free'
                psetvar[index][1] = 'free'
                updateIniFile(MSXPIHOME+'/msxpi.ini',psetvar)
                return RC_SUCCESS
            else:
                psetvar[index][1] = pvalue
                updateIniFile(MSXPIHOME+'/msxpi.ini',psetvar)
                return RC_SUCCESS
        index += 1
                
    # Did not find the Var - User is tryign to add a new one
    # Check if there is a slot, then add new variable
    for index in range(0,len(psetvar)):
        if (psetvar[index][0] == "free" and psetvar[index][1] == "free"):
            psetvar[index][0] = pvar
            psetvar[index][1] = pvalue
            updateIniFile(MSXPIHOME+'/msxpi.ini',psetvar)
            return RC_SUCCESS

    return RC_FAILED

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
    
def pwifi():
    print("pwifi")
    global psetvar
    wifissid = getMSXPiVar('WIFISSID')
    wifipass = getMSXPiVar('WIFIPWD')
    wificountry = getMSXPiVar('WIFICOUNTRY')

    rc,cmd = readParameters("", False)
    if rc != RC_SUCCESS:
        return RC_FAILED
        
    if (cmd[:2] == "/h"):
        sendmultiblock("Pi:Usage:\npwifi display | set".encode(), BLKSIZE, RC_FAILED)
        return RC_SUCCESS

    if (cmd[:1] == "s" or cmd[:1] == "S"):
        if hostType == "pi":
            wifisetcmd = 'sudo nmcli device wifi connect "' + wifissid + '" password "' + wifipasss + '"'
            prun(wifisetcmd)
        else:
            sendmultiblock(b'Parameter not supported in this platform', BLKSIZE, RC_SUCCESS)
    else:
        if hostType == "pi":
            prun("ip a | grep '^1\\|^2\\|^3\\|^4\\|inet'|grep -v inet6")
        else:
            prun("ipconfig")
    
    return RC_SUCCESS

def pver():
    print("pver()")
    global version,build
    ver = "MSXPi Server Version "+version+" Build "+ BuildId
    rc = sendmultiblock(ver.encode(), BLKSIZE, RC_SUCCESS)
    return rc
    
def irc():

    print("irc")

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
            sendmultiblock(ircmsg.encode(), BLKSIZE, RC_SUCCESS)
        elif cmd[:3] == "msg":
            ircsock.setblocking(0);
            ircsock.send(("PRIVMSG "+cmd[4:] +"\r\n").encode())
            sendmultiblock("Pi:Ok\n".encode(), BLKSIZE, RC_SUCCNOSTD)
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
            sendmultiblock(ircmsg.encode(), BLKSIZE, rc)

        elif cmd[:4] == 'read':
  
            print("irc:read")
            
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
    
            sendmultiblock(ircmsg.encode(), BLKSIZE, rc)
            
        elif cmd[:5] == 'names':
            print("names:",cmd)
            ircsock.send((cmd+"\r\n").encode())
            ircmsg = ''
            ircmsg = ircmsg + ircsock.recv(2048).decode("UTF-8")
            ircmsg = ircmsg.strip('\n\r')
            print("names:",ircmsg)
            ircmsg = "Users on channel " #+ ircmsg.split('=',1)[1]
            sendmultiblock(ircmsg.encode(), BLKSIZE, RC_SUCCESS)
        elif cmd[:4] == 'quit':
            ircsock.send(("/quit\r\n").encode())
            ircsock.close()
            sendmultiblock("Pi:leaving room\r\n".encode(),BLKSIZE, RC_SUCCESS)
        elif cmd[:4] == 'part':
            print("part:")
            ircsock.send(("/part\r\n").encode())
            ircsock.close()
            sendmultiblock("Pi:leaving room\n".encode(),BLKSIZE, RC_SUCCESS)
        else:
            print("irc:no valid command received")
            sendmultiblock("Pi:No valid command received".encode(),BLKSIZE, rc)
    except Exception as e:
        print("irc:Caught exception"+str(e))
        sendmultiblock("Pi:"+str(e).encode(), BLKSIZE, rc)

def py():
    print('python')
    rc,data = recvdata(BLKSIZE)
    cmd = data.decode().split("\x00")[0]
    if rc == RC_SUCCESS:
        try:
            f = StringIO()
            with redirect_stdout(f):
                exec(cmd)
            buf = f.getvalue()
            sendmultiblock(buf.encode(), BLKSIZE, RC_SUCCESS)
        except Exception as e:
            print("python:",str(e).encode())
            sendmultiblock(("Pi:Error - "+str(e)).encode(), BLKSIZE, RC_FAILED)
    else:
        sendmultiblock('Pi:Error'.encode(), BLKSIZE, rc)
        
def dosinit():
    
    global msxdos1boot
        
    rc,data = recvdata(BLKSIZE)
    if rc == RC_SUCCESS:
        flag = data.decode().split("\x00")[0]
        if flag == '1':
            dskioini()
        else:
            msxdos1boot = False
    
    #print (hex(rc))
    return rc
    
def dskioini():
    print("dskioini")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data
    
    # Initialize disk system parameters
    msxdos1boot = True
    sectorInfo = [0,0,0,0]
    # Load the disk images into a memory mapped variable
    rc , drive0Data = msxdos_inihrd(getMSXPiVar('DriveA'))
    rc , drive1Data = msxdos_inihrd(getMSXPiVar('DriveB'))

def dskiords():
    print("dskiords")

    DOSSCTSZ = SECTORSIZE - 3
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data
    if not msxdos1boot:
        dskioini()
        
    initdataindex = sectorInfo[3]*DOSSCTSZ
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    #print("dskiords:deviceNumber=",sectorInfo[0])
    #print("dskiords:numsectors=",sectorInfo[1])
    #print("dskiords:mediaDescriptor=",sectorInfo[2])
    #print("dskiords:initialSector=",sectorInfo[3])
    #print("dskiords:blocksize=",DOSSCTSZ)
    
    while sectorcnt < numsectors:
        #print("dskiords:",sectorcnt)
        if sectorInfo[0] == 0:
            buf = drive0Data[initdataindex+(sectorcnt*DOSSCTSZ):initdataindex+DOSSCTSZ+(sectorcnt*DOSSCTSZ)]
        else:
            buf = drive1Data[initdataindex+(sectorcnt*DOSSCTSZ):initdataindex+DOSSCTSZ+(sectorcnt*DOSSCTSZ)]
        rc = senddata(buf,DOSSCTSZ)
        sectorcnt += 1
        
        if  rc == RC_SUCCESS:
            pass
            #print("dskiords: checksum is a match")
        else:
            print("dskiords: checksum error")
            break
 
def dskiowrs():
    print("dskiowrs")
    
    DOSSCTSZ = SECTORSIZE - 3
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data
    if not msxdos1boot:
        dskioini()
        
    initdataindex = sectorInfo[3]*DOSSCTSZ
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    #print("dskiowrs:deviceNumber=",sectorInfo[0])
    #print("dskiowrs:numsectors=",sectorInfo[1])
    #print("dskiowrs:mediaDescriptor=",sectorInfo[2])
    #print("dskiowrs:initialSector=",sectorInfo[3])
    #print("dskiowrs:blocksize=",DOSSCTSZ)
    
    while sectorcnt < numsectors:
        rc,buf = recvdata(DOSSCTSZ)
        if  rc == RC_SUCCESS:
            #print("dskiowrs: checksum is a match")
            if sectorInfo[0] == 0:
                drive0Data[initdataindex+(sectorcnt*DOSSCTSZ):initdataindex+DOSSCTSZ+(sectorcnt*DOSSCTSZ)] = buf
            else:
                drive1Data[initdataindex+(sectorcnt*DOSSCTSZ):initdataindex+DOSSCTSZ+(sectorcnt*DOSSCTSZ)] = buf
            sectorcnt += 1
        else:
            print("dskiowrs: checksum error")
            break
                  
def dskiosct():
    print("dskiosct")

    DOSSCTSZ = SECTORSIZE - 3
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data
    if not msxdos1boot:
        dskioini()

    route = 1
    
    if route == 1:             
        rc,buf = recvdata(5)
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
            
    else:
        # Syncronize with MSX
        while True:
            rc, pibyte = piexchangebyte()
            if rc == RC_FAILED or pibyte == READY:
                break
        
        if rc == RC_FAILED:
            return
            
        rc, sectorInfo[0] = piexchangebyte()
        rc, sectorInfo[1] = piexchangebyte()
        rc, sectorInfo[2] = piexchangebyte()
        rc, byte_lsb = piexchangebyte()
        rc, byte_msb = piexchangebyte()
        sectorInfo[3] = byte_lsb + 256 * byte_msb
        rc, msxcrc = piexchangebyte()

        crc = 0xFF
        crc = crc ^ (sectorInfo[0])        
        crc = crc ^ (sectorInfo[1])
        crc = crc ^ (sectorInfo[2])
        crc = crc ^ (byte_lsb)        
        crc = crc ^ (byte_msb)    
        piexchangebyte(crc)
      
        if crc != msxcrc:
            print("dos_sct: crc error")
          
    #print("dskiosct:deviceNumber=",sectorInfo[0])
    #print("dskiosct:numsectors=",sectorInfo[1])
    #print("dskiosct:mediaDescriptor=",sectorInfo[2])
    #print("dskiosct:initialSector=",sectorInfo[3])
       
def recvdata(bytecounter = BLKSIZE):

    print(f"recvdata():")

    if hostType == "pi":
        th = threading.Timer(3.0, exitDueToSyncError)
            
    retries = GLOBALRETRIES
    while retries > 0:
        retries -= 1
        
        # Syncronize with MSX
        while True:
            rc, pibyte = piexchangebyte()
            if rc == RC_FAILED or pibyte == READY:
                break
        
        if rc == RC_FAILED:
            return RC_FAILED, None
            
        data = bytearray()
        chksum = 0
        while(bytecounter > 0 ):
            rc, msxbyte = piexchangebyte()
            if rc == RC_FAILED:
                return RC_FAILED, None
            data.append(msxbyte)
            chksum += msxbyte
            bytecounter -= 1

        # Receive the CRC
        rc, msxsum = piexchangebyte()
        
        # Send local CRC - only 8 right bits
        thissum_r = (chksum % 256)              # right 8 bits
        thissum_l = (chksum >> 8)                 # left 8 bits
        thissum = ((thissum_l + thissum_r) % 256)
        piexchangebyte(thissum)
        
        if (thissum == msxsum):
            rc = RC_SUCCESS
            #print("recvdata: checksum is a match")
            if hostType == "pi":
                th.cancel()
            break
        else:
            rc = RC_TXERROR
            print("recvdata: checksum error")
            if hostType == "pi":
                th.start()
        
    return rc,data

def senddata(data, blocksize = BLKSIZE):
    
    
    print(f"senddata():")
    
    if hostType == "pi":
        th = threading.Timer(3.0, exitDueToSyncError)
        th.start()
    
    rc = RC_SUCCESS
    retries = GLOBALRETRIES
    while retries > 0:
        retries -= 1
        # Syncronize with MSX
        while True:
            rc, pibyte = piexchangebyte()
            if rc == RC_FAILED or pibyte == READY:
                break
        
        if rc == RC_FAILED:
            return RC_FAILED
        
        #print("senddata(): Sync acquired")
        byteidx = 0
        chksum = 0
    
        while(byteidx < blocksize):
            byte0 = data[byteidx]
            if type(byte0) is int:
                byte = byte0
            else:
                byte = ord(byte0)

            chksum += byte
            piexchangebyte(byte)
            byteidx += 1
        
        #print("senddata(): calculating checksum")
        # Send local CRC - only 8 right bits
        thissum_r = (chksum % 256)              # right 8 bits
        thissum_l = (chksum >> 8)                 # left 8 bits
        thissum = ((thissum_l + thissum_r) % 256)
        piexchangebyte(thissum)
    
        # Receive the CRC
        rc, msxsum = piexchangebyte()
            
        if (thissum == msxsum):
            rc = RC_SUCCESS
            #print("senddata: checksum is a match")
            if hostType == "pi":
                th.cancel()
            break
        else:
            rc = RC_TXERROR
            print("senddata: checksum error")
    
    return rc

def sendmultiblock(buf, blocksize = BLKSIZE, rc = RC_SUCCESS):
    
    global hostType
    
    #print(f"sendmultiblock(): {buf}")

    numblocks = math.ceil((len(buf)+3)/blocksize)
    
    # If buffer small or equal to BLKSIZE
    if numblocks == 1:  # Only one block to transfer
        print(f"1 block rc = {hex(rc)} , buf size = {len(buf)} blocksize = {blocksize}")
        print(f"buf = {buf}")
        data = bytearray(blocksize)
        data[0] = rc
        data[1] = int(len(buf) % 256)
        data[2] = int(len(buf) >> 8)
        data[3:len(buf)] = buf
        rc = senddata(data[:blocksize],blocksize)
    else: # Multiple blocks to transfer
        idx = 0
        thisblk = 0
        print(f"sendmultiblock(): Blocks to send = {numblocks}")
        while thisblk < numblocks:
            print(f"sendmultiblock(): block {thisblk}")
            data = bytearray(blocksize)
            if thisblk + 1 == numblocks:
                data[0] = rc # Last block - send original RC
                datasize = len(buf) - idx
                data[1] = datasize % 256
                data[2] = datasize >> 8
            else:
                data[0] = RC_READY  # This is not last block
                datasize = blocksize - 3
                data[1] = datasize % 256
                data[2] = datasize >> 8
            data[3:datasize] = buf[idx:idx + datasize]
            
            # monitor disconnections on non-Raspberry Pi platforms
            
            if hostType == "pi":
                rc = senddata(data,blocksize)
                if rc == RC_FAILED:
                    return RC_FAILED
                idx += (blocksize - 3)
                thisblk += 1           
            else:
                conn.settimeout(5.0)  # Set timeout before sending
                try:
                    rc = senddata(data,blocksize)
                    if rc == RC_FAILED:
                        return RC_FAILED
                    idx += (blocksize - 3)
                    thisblk += 1
                    conn.settimeout(None)  # Optional: restore to blocking mode
                except socket.timeout:
                    print("Send timeout: peer not responding.")
                    break
                    conn.settimeout(None)  # Optional: restore to blocking mode

    return rc

# This is the function that read parameters for all commands
# The parameters have following use:
# errorMsg: this is the error message to return to MSX if there
#  was an error reading the parameter
# needParm: This flag indicates if a parameters must have been
#  passed or if parameters are optional.
#  Some commands (such as chatgpt.com) must have a parameter,
#  therefore needParam must be True
def readParameters(errorMsg, needParm=False):
    print("readparms():")
    rc, data = recvdata(BLKSIZE)

    if rc != RC_SUCCESS:
        print(f"Pi:Error reading parameters")
        encodederrorMsg = ('Pi:Error reading parameters').encode()
        sendmultiblock(encodederrorMsg, BLKSIZE, RC_FAILED)
        return RC_FAILED, None

    parms = data.decode().split("\x00")[0].strip()
    if needParm and not parms:
        print(f"Pi:Error - {errorMsg}")
        encodederrorMsg = ('Pi:Error - ' + errorMsg).encode()
        sendmultiblock(encodederrorMsg, BLKSIZE, RC_FAILED)
        return RC_FAILED, None

    print(f"Parameters:{parms}")
    return RC_SUCCESS, parms

def prestart():
    print("Restarting MSXPi Server")
    exitDueToSyncError()
    
def preboot():
    print("Rebooting Raspberry Pi")
    os.system("sudo reboot")
    
def pshut():
    print("Shutting down Raspberry Pi")
    os.system("sudo shutdown -h now")
    
def exitDueToSyncError():
    print("Sync error. Recycling MSXPi-Server")
    os.system("/home/pi/msxpi/kill.sh")

def updateIniFile(fname,memvar):
    f = open(fname, 'w')
    for v in memvar:
        f.writelines('var '+v[0]+'='+v[1]+'\n')
    f.close()

def apitest():
    print("apitest")

    # This command requires parameter
    rc, data = readParameters("This command requires a parameter", False)
    
    # Stops if MSX did not send the query for OpenAI
    if rc == RC_FAILED:
        return RC_FAILED
    
    # Send response to CALL MSXPI - It will always expect a response
    rc = sendmultiblock(('Pi:CALL MSXPI parameters:' + buf1).encode(), BLKSIZE, RC_SUCCESS)
        
    # Now Receive additional data sent with CALL MSXPISEND
    rc,data = recvdata(BLKSIZE)
    #print("Additional data sent by CALL MSXPISEND:",data)
    
    #print("Extracting only ascii bytes and setting reponse...")
    buf2 = data.decode().split("\x00")[0]

    #print("Sending response: ",buf2)
    rc = sendmultiblock(('Pi:CALL MSXPISEND data:' + buf2).encode(), BLKSIZE, RC_SUCCESS)
    
def chatgpt():
    print("chatgpt()")
    api_key = getMSXPiVar('OPENAIKEY')
    if not api_key:
        print('Pi:Error - OPENAIKEY is not defined. Define your key with PSET or add to msxpi.ini')
        sendmultiblock(b'Pi:Error - OPENAIKEY is not defined. Define your key with PSET or add to msxpi.ini', BLKSIZE, RC_FAILED)
        return RC_FAILED

    # This command requires parameter
    rc, query = readParameters("This command requires a query", False)
    
    # Stops if MSX did not send the query for OpenAI
    if rc == RC_FAILED:
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
            sendmultiblock(response_text.encode(), BLKSIZE, RC_SUCCESS)
        else:
            sendmultiblock(openai_response.encode(), BLKSIZE, RC_FAILED)
    except Exception as e:
        error_msg = f"Pi:Error - {str(e)}"
        print(error_msg)
        sendmultiblock(error_msg.encode(), BLKSIZE, RC_FAILED)
  
def initialize_connection():
    """Set up the server socket and wait for a client connection."""
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind((HOST, PORT))
    s.listen(1)
    print(f"[Python Server] Listening on {HOST}:{PORT}...")
    conn, addr = s.accept()
    print(f"[Python Server] Connected by {addr}")
    return conn

""" ============================================================================
    msxpi-server.py
    main program starts here
    ============================================================================
"""

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

# irc
channel = "#msxpi"
allchann = []
ircsock = None
errcount = 0
msxdos1boot = False

# GPIO Pins is now defined by the user
SPI_CS = int(getMSXPiVar("SPI_CS"))
SPI_SCLK = int(getMSXPiVar("SPI_SCLK"))
SPI_MOSI = int(getMSXPiVar("SPI_MOSI"))
SPI_MISO = int(getMSXPiVar("SPI_MISO"))
RPI_READY = int(getMSXPiVar("RPI_READY"))

print("Starting MSXPi Server Version ",version,"Build",BuildId)

hostType = detect_host()

if hostType == "pi":
    import RPi.GPIO as GPIO
    init_spi_bitbang()
    GPIO.output(RPI_READY, GPIO.LOW)
    print("Raspberry Pi GPIO initialized\n")
else:
    conn = initialize_connection()
    print(f"{hostType} socket initialized\n")

try:
    while True:

        try:
            print("st_recvcmd: waiting command")
            rc,buf = recvdata(CMDSIZE)

            if (rc == RC_SUCCESS):
                if buf[0] == 0:
                    fullcmd=''
                else:
                    fullcmd = buf.decode().split("\x00")[0]

                #print(f"Received command: {fullcmd}")
                cmd = fullcmd.split()[0].lower()
                parms = fullcmd[len(cmd)+1:]
                # Executes the command (first word in the string)
                # And passes the whole string (including command name) to the function
                # globals()['use_variable_as_function_name']() 
                globals()[cmd.strip()]()
        except Exception as e:
            errcount += 1
            print(str(e))
            recvdata(BLKSIZE)       # Read & discard parameters to avoid sync errors
            sendmultiblock(("Pi:Error - "+str(e)).encode(),BLKSIZE, RC_FAILED)

except KeyboardInterrupt:
    if detect_host() == "Raspberry Pi":
        GPIO.cleanup() # cleanup all GPIO
    print("Terminating msxpi-server")
