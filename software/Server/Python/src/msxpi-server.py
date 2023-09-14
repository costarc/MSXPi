#!/usr/bin/python3
# External module imports
import RPi.GPIO as GPIO
import time
import subprocess
from urllib.request import urlopen
import mmap
import fcntl,os
import sys
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
import openai

version = "1.1"
BuildId = "20230914.624"

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

    global SPI_CS
    global SPI_SCLK
    global SPI_MOSI
    global SPI_MISO
    global RPI_READY
    GPIO.output(SPI_SCLK, GPIO.HIGH)
    #time.sleep(SPI_SCLK_HIGH_TIME)
    GPIO.output(SPI_SCLK, GPIO.LOW)
    #time.sleep(SPI_SCLK_LOW_TIME)

def SPI_MASTER_transfer_byte(byte_out):
    #print "transfer_byte:sending",hex(byte_out)
    byte_in = 0
    tick_sclk()
    for bit in [0x80,0x40,0x20,0x10,0x8,0x4,0x2,0x1]:
        #print(".")
        if (int(byte_out) & bit):
            GPIO.output(SPI_MISO, GPIO.HIGH)
        else:
            GPIO.output(SPI_MISO, GPIO.LOW)

        GPIO.output(SPI_SCLK, GPIO.HIGH)
        #time.sleep(SPI_SCLK_HIGH_TIME)
        
        if GPIO.input(SPI_MOSI):
            byte_in |= bit
    
        GPIO.output(SPI_SCLK, GPIO.LOW)
        #time.sleep(SPI_SCLK_LOW_TIME)

    tick_sclk()
    #print "transfer_byte:received",hex(byte_in),":",chr(byte_in)
    return byte_in

def piexchangebyte(byte_out=0):
    global SPI_CS
    global SPI_SCLK
    global SPI_MOSI
    global SPI_MISO
    global RPI_READY
    
    rc = RC_SUCCESS
    
    GPIO.output(RPI_READY, GPIO.HIGH)
    while(GPIO.input(SPI_CS)):
        pass

    byte_in = SPI_MASTER_transfer_byte(byte_out)
    GPIO.output(RPI_READY, GPIO.LOW)

    #print "piexchangebyte: received:",hex(mymsxbyte)
    return byte_in

def piexchangebytewithtimeout(byte_out=0,twait=5):
    global SPI_CS
    global SPI_SCLK
    global SPI_MOSI
    global SPI_MISO
    global RPI_READY
    rc = RC_SUCCESS
    
    t0 = time.time()
    GPIO.output(RPI_READY, GPIO.HIGH)
    while((GPIO.input(SPI_CS)) and (time.time() - t0) < twait):
        pass

    t1 = time.time()

    if ((t1 - t0) > twait):
        return ABORT

    byte_in = SPI_MASTER_transfer_byte(byte_out)
    GPIO.output(RPI_READY, GPIO.LOW)

    #print "piexchangebyte: received:",hex(mymsxbyte)
    print("io:",byte_in)
    return byte_in

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
    elif (path.startswith('m:')):
        urltype = 1 # this is a network path
        newpath = getMSXPiVar('DriveM') + '/' + path.split(':')[1]
    elif (path.startswith('r1:')):
        urltype = 1 # this is a network path
        newpath = getMSXPiVar('DriveR1') + '/' + path.split(':')[1]
    elif (path.startswith('r2:')):
        urltype = 1 # this is a network path
        newpath = getMSXPiVar('DriveR2') + '/' + path.split(':')[1]
    elif (path.startswith('http') or \
        path.startswith('ftp') or \
        path.startswith('nfs') or \
        path.startswith('smb')):
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
    print("msxdos_inihrd",filename)
    
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
    print("prun")
    rc = RC_SUCCESS
    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        rc,data = recvdata(BLKSIZE)
        
        if data[0] == 0:
            cmd=''
        else:
            cmd = data.decode().split("\x00")[0]
    
    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        rc = RC_FAILED
        sendmultiblock("Syntax: prun <command> <::> command. To  pipe a command to other, use :: instead of |".encode(),BLKSIZE,rc)
    else:
        cmd = cmd.replace('::','|')
        try:
            p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
            buf = p.stdout.read().decode()
            err = (p.stderr.read().decode())
            if len(err) > 0 and not ('0K ....' in err): # workaround for wget false positive
                rc = RC_FAILED
                buf = ("Pi:Error - " + str(err))
            elif len(buf) == 0:
                rc = RC_SUCCESS
                buf = "Pi:Ok"

            sendmultiblock(buf.encode(), BLKSIZE, RC_SUCCESS)

        except Exception as e:
            print("prun: exception:"+str(e))
            rc = RC_FAILED
            sendmultiblock(("Pi:Error - "+str(e)).encode(),BLKSIZE, rc)

    #print(hex(rc))
    return rc

def pdir():

    print("pdir")
    rc = RC_SUCCESS
    basepath = getMSXPiVar('PATH')
    rc,data = recvdata()
    if data[0] == 0:
        userPath=''
    else:
        userPath = data.decode().split("\x00")[0]

    pathType, path = pathExpander(userPath, basepath)

    try:
        if pathType == 0:
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

    #print("pdir:exiting rc:",hex(rc))
    return rc

def pcd():
    
    print("pcd")
    rc = RC_SUCCESS
    basepath = getMSXPiVar('PATH')
    rc,data = recvdata()
    
    if data[0] == 0:
        userPath=''
    else:
        userPath = data.decode().split("\x00")[0]
        
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
    
def pcopy():

    buf = bytearray(BLKSIZE)
    rc = RC_SUCCESS

    global psetvar,GLOBALRETRIES
    basepath = getMSXPiVar('PATH')
    
    # Receive parameters -
    rc,data = recvdata(BLKSIZE)
    
    if data[0] == 0:
        userPath=''
    else:
        userPath = data.decode().split("\x00")[0]
                   
    if len(userPath) == 0 or userPath.lower().startswith('/h'):
        buf = 'Syntax:\n'
        buf = buf + 'pcopy </z> remotefile <localfile>\n'
        buf = buf +'Valid devices:\n'
        buf = buf +'/, path, http, ftp, nfs, smb, m:, r1:, r2:\n'
        buf = buf + '/z decompress file\n'
        buf = buf + 'm:, r1: r2: virtual remote devices'

        rc = sendmultiblock(buf.encode(), BLKSIZE, RC_FAILED)
        return rc

    fname2 = ''
    expandedFn = ''
    parms = userPath.split()
    if '/z' in userPath.lower():
        expand = True
        pathType, path = pathExpander(parms[1], basepath)
        if len(parms) > 2:
            fname2 = parms[2]
    else:
        expand = False
        pathType, path = pathExpander(parms[0], basepath)
        if len(parms) > 1:
            fname2 = parms[1]

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
        try:
            urlhandler = urlopen(path)
            buf = urlhandler.read()
            filesize = len(buf)
        except Exception as e:
            rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)
            return RC_FAILED

    if rc == RC_SUCCESS:
        # if /z passed, will uncompress the file
        if expand:
            tmpfn0 = path.split('/')
            tmpfn = tmpfn0[len(tmpfn0)-1]
            #print("Entered expand")
            os.system('rm /tmp/msxpi/* 2>/dev/null')
            tmpfile = open('/tmp/' + tmpfn, 'wb')
            tmpfile.write(buf)
            tmpfile.close()
            if ".lzh" in tmpfn:
                cmd = '/usr/bin/lhasa -xfiw=/tmp/msxpi /tmp/' + tmpfn
                p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
                perror = (p.stderr.read().decode())
                rc = p.poll()
                if rc!=0:
                    rc = RC_FAILED
            else:
                cmd = '/usr/bin/unar -f -o /tmp/msxpi /tmp/' + tmpfn
                p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
                perror = (p.stderr.read().decode())
                rc = p.poll()
                if rc!=0:
                    rc = RC_FAILED
            
            if rc == 0:
                fname1 = os.listdir('/tmp/msxpi')[0]
                expandedFn = fname1
                fname1 = '/tmp/msxpi/' + fname1

                try:
                    with open(fname1, mode='rb') as f:
                        buf = f.read()

                    filesize = len(buf)
                    rc = RC_SUCCESS
                    
                except Exception as e:
                    rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)
                    return RC_FAILED
       
            else:
                rc = sendmultiblock(('Pi:Error - ' + perror).encode(), BLKSIZE, RC_FAILED)
                return RC_FAILED
                
    if rc == RC_SUCCESS:
        if filesize == 0:
            rc = sendmultiblock("Pi:Error - File size is zero bytes".encode(), BLKSIZE, RC_FAILED)
            return RC_FAILED

        else:
            if not msxdos1boot: # Boot was not from MSXPi disk drive
                if fname2 == '':
                    fname2=path.split("/")[len(path.split("/"))-1]
                rc = ini_fcb(fname2,filesize)
                if rc != RC_SUCCESS:
                    print("pcopy: ini_fcb failed")
                    return rc
                # This will send the file to MSX, for pcopy to write it to disk
                rc = sendmultiblock(buf,SECTORSIZE, rc)
            
            else:# Booted from MSXPi disk drive (disk images)
                # this routine will write the file directly to the disk image in RPi
                try:
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
                    sendmultiblock("Pi:Ok".encode(), BLKSIZE, RC_TERMINATE)
                except Exception as e:
                    rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)
            
    #print(hex(rc))
    return rc

def ploadr():

    buf = bytearray(BLKSIZE)
    rc = RC_SUCCESS

    global psetvar,GLOBALRETRIES
    basepath = getMSXPiVar('PATH')
    
    # Receive parameters -
    rc,data = recvdata(BLKSIZE)
    
    if data[0] == 0:
        userPath=''
    else:
        userPath = data.decode().split("\x00")[0]
                   
    if len(userPath) == 0 or userPath.lower().startswith('/h'):
        buf = 'Syntax:\n'
        buf = buf + 'ploadr </z> remotefile\n'
        buf = buf +'Valid devices:\n'
        buf = buf +'/, path, http, ftp, nfs, smb, m:, r1:, r2:\n'
        buf = buf + '/z decompress file\n'
        buf = buf + 'm:, r1: r2: virtual remote devices'

        rc = sendmultiblock(buf.encode(), BLKSIZE, RC_FAILED)
        return rc

    expandedFn = ''
    parms = userPath.split()
    if '/z' in userPath.lower():
        expand = True
        pathType, path = pathExpander(parms[1], basepath)
    else:
        expand = False
        pathType, path = pathExpander(parms[0], basepath)

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
        try:
            urlhandler = urlopen(path)
            buf = urlhandler.read()
            filesize = len(buf)
        except Exception as e:
            rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)
            return RC_FAILED

    if rc == RC_SUCCESS:
        # if /z passed, will uncompress the file
        if expand:
            tmpfn0 = path.split('/')
            tmpfn = tmpfn0[len(tmpfn0)-1]
            #print("Entered expand")
            os.system('rm /tmp/msxpi/* 2>/dev/null')
            tmpfile = open('/tmp/' + tmpfn, 'wb')
            tmpfile.write(buf)
            tmpfile.close()
            if ".lzh" in tmpfn:
                cmd = '/usr/bin/lhasa -xfiw=/tmp/msxpi /tmp/' + tmpfn
                p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
                perror = (p.stderr.read().decode())
                rc = p.poll()
                if rc!=0:
                    rc = RC_FAILED
            else:
                cmd = '/usr/bin/unar -f -o /tmp/msxpi /tmp/' + tmpfn
                p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
                perror = (p.stderr.read().decode())
                rc = p.poll()
                if rc!=0:
                    rc = RC_FAILED
            
            if rc == 0:
                fname1 = os.listdir('/tmp/msxpi')[0]
                expandedFn = fname1
                fname1 = '/tmp/msxpi/' + fname1

                try:
                    with open(fname1, mode='rb') as f:
                        buf = f.read()

                    filesize = len(buf)
                    rc = RC_SUCCESS
                    
                except Exception as e:
                    rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, RC_FAILED)
                    return RC_FAILED
       
            else:
                rc = sendmultiblock(('Pi:Error - ' + perror).encode(), BLKSIZE, RC_FAILED)
                return RC_FAILED
                
    if rc == RC_SUCCESS:
        if filesize == 0:
            rc = sendmultiblock("Pi:Error - File size is zero bytes".encode(), BLKSIZE, RC_FAILED)
            return RC_FAILED

        else:
            # Send the file to MSX
            rc = sendmultiblock(buf,SECTORSIZE, rc)
    
    print(hex(rc))
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
    
    print("Date:",now,pdate)
    
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
    rc = RC_SUCCESS
    
    rc,data = recvdata(BLKSIZE)
    print("pplay:",data)
        
    if data[0] == 0:
        buf = "Syntax:\npplay play|loop|pause|resume|stop|getids|getlids|list <filename|processid|directory|playlist|radio>\nExemple: pplay play music.mp3"
        sendmultiblock(buf.encode(), BLKSIZE, RC_SUCCESS)
        return rc
    else:
        msxparms = data.decode().split("\x00")[0]
        parmslist = msxparms.split(" ")
        cmd = parmslist[0]
        if len(parmslist) > 1:
            parms = msxparms.split(" ")[1].split("\x00")[0]
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
        sendmultiblock(("Pi:Error - "+str(e)).encode(),BLKSIZE, rc)

    #print (hex(rc))
    return rc
    
def pvol():
    rc = RC_SUCCESS
    
    rc,data = recvdata(BLKSIZE)

    if data[0] == 0:
        vol=''
    else:
        vol = data.decode().split("\x00")[0]
        
    rc = prun("mixer set PCM -- "+vol)
    
    print (hex(rc))
    return rc

def pset(varn = '', varv = ''):
    
    print("pset")
    
    global psetvar,drive0Data,drive1Data

    if varn == '':
        
        rc,data = recvdata(BLKSIZE)
        buf = ''
        if data[0] == 0:
            for index in range(0,len(psetvar)):
                print(psetvar[index])
                buf = buf + psetvar[index][0]+'='+psetvar[index][1]+'\n'
            rc = sendmultiblock(buf.encode(), BLKSIZE, RC_SUCCESS)
            return RC_SUCCESS
        else:
            buf = data.decode().split("\x00")[0]
            if  (buf.lower() == "/h" or buf.lower() == "/help"):
                rc = sendmultiblock("Syntax:\npset                    Display variables\npset varname   varvalue   Set varname to varvalue\npset varname            Delete variable     varname".encode(), BLKSIZE, RC_FAILED)
                return rc

        varname = buf.split(" ")[0]
        varvalue = buf.replace(varname,'',1).strip()
    else:
        varname = varn
        varvalue = varv
        
    print("pset:",varname, varvalue)
    
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

    global psetvar
    wifissid = getMSXPiVar('WIFISSID')
    wifipass = getMSXPiVar('WIFIPWD')
    wificountry = getMSXPiVar('WIFICOUNTRY')

    rc,data = recvdata()

    if data[0] == 0:
        parms=''
    else:
        parms = data.decode().split("\x00")[0]

    cmd=parms.strip()

    if (cmd[:2] == "/h"):
        sendmultiblock("Pi:Usage:\npwifi display | set".encode(), BLKSIZE, RC_FAILED)
        return RC_SUCCESS

    if (cmd[:1] == "s" or cmd[:1] == "S"):
        setWiFiCountryCMD = "sudo raspi-config nonint do_wifi_country " + wificountry
        os.system(setWiFiCountryCMD)
        buf = "country=" + wificountry + "\n\nctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\nupdate_config=1\nnetwork={\n"
        buf = buf + "\tssid=\"" + wifissid
        buf = buf + "\"\n\tpsk=\"" + wifipass
        buf = buf + "\"\n}\n"

        os.system("sudo cp -f /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf.bak")
        f = open(RAMDISK + "/wpa_supplicant.conf","w")
        f.write(buf)
        f.close()
        os.system("sudo cp -f " + RAMDISK + "/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant.conf")
        cmd = cmd.strip().split(" ")
        if (len(cmd) == 2 and cmd[1] == "wlan1"):
            prun("sudo ip link set wlan1 down && sleep 1 && sudo ip link set wlan1 up")
        else:
            prun("sudo ip link set wlan0 down && sleep 1 && sudo ip link set wlan0 up")
    else:
        prun("ip a | grep '^1\\|^2\\|^3\\|^4\\|inet'|grep -v inet6")
    
    return RC_SUCCESS

def pver():
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
        while piexchangebyte() != READY:  # was 0x9F:
            pass
            
        sectorInfo[0] = piexchangebyte()
        sectorInfo[1] = piexchangebyte()
        sectorInfo[2] = piexchangebyte()
        byte_lsb = piexchangebyte()
        byte_msb = piexchangebyte()
        sectorInfo[3] = byte_lsb + 256 * byte_msb
        msxcrc = piexchangebyte()

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
       
def recvdata( bytecounter = BLKSIZE):

    print("recvdata")

    th = threading.Timer(3.0, exitDueToSyncError)
            
    retries = GLOBALRETRIES
    while retries > 0:
        retries -= 1
        
        # Syncronize with MSX
        while piexchangebyte() != READY: # WAS 0x9F:
            pass
            
        data = bytearray()
        chksum = 0
        while(bytecounter > 0 ):
            msxbyte = piexchangebyte()
            data.append(msxbyte)
            chksum += msxbyte
            bytecounter -= 1

        # Receive the CRC
        msxsum = piexchangebyte()
        
        # Send local CRC - only 8 right bits
        thissum_r = (chksum % 256)              # right 8 bits
        thissum_l = (chksum >> 8)                 # left 8 bits
        thissum = ((thissum_l + thissum_r) % 256)
        piexchangebyte(thissum)
        
        if (thissum == msxsum):
            rc = RC_SUCCESS
            #print("recvdata: checksum is a match")
            th.cancel()
            break
        else:
            rc = RC_TXERROR
            print("recvdata: checksum error")
            th.start()
        
    #print (hex(rc))
    return rc,data

def senddata(data, blocksize = BLKSIZE):
    
    print("senddata")

    th = threading.Timer(3.0, exitDueToSyncError)
    th.start()
            
    retries = GLOBALRETRIES
    while retries > 0:
        retries -= 1
        
        # Syncronize with MSX
        while piexchangebyte() != READY: # WAS 0x9F:
            pass
            
        byteidx = 0
        chksum = 0
    
        while(byteidx < blocksize):
            #if (byteidx == 0) or (byteidx > 499):
            #    print(byteidx)
            pibyte0 = data[byteidx]
            if type(pibyte0) is int:
                pibyte = pibyte0
            else:
                pibyte = ord(pibyte0)

            chksum += pibyte
            piexchangebyte(pibyte)
            byteidx += 1
        
        # Send local CRC - only 8 right bits
        thissum_r = (chksum % 256)              # right 8 bits
        thissum_l = (chksum >> 8)                 # left 8 bits
        thissum = ((thissum_l + thissum_r) % 256)
        piexchangebyte(thissum)
    
        # Receive the CRC
        msxsum = piexchangebyte()
            
        if (thissum == msxsum):
            rc = RC_SUCCESS
            #print("senddata: checksum is a match")
            th.cancel()
            break
        else:
            rc = RC_TXERROR
            print("senddata: checksum error")
    
    #print (hex(rc))
    return rc

def sendmultiblock(buf, blocksize = BLKSIZE, rc = RC_SUCCESS):

    print("sendmultiblock")

    numblocks = math.ceil(len(buf)/(blocksize - 3))
    
    # If buffer small or equal to BLKSIZE
    if numblocks == 1:  # Only one block to transfer
        data = bytearray(blocksize)
        data[0] = rc
        data[1] = int(len(buf) % 256)
        data[2] = int(len(buf) >> 8)
        data[3:len(buf)] = buf
        senddata(data[:blocksize],blocksize)
    else: # Multiple blocks to transfer
        idx = 0
        thisblk = 0
        while thisblk < numblocks:
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
            senddata(data,blocksize)
            idx += (blocksize - 3)
            thisblk += 1
                        
    return rc
    
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
    
    # Parameters have always a fixed size: BLKSIZE
    rc,data = recvdata(BLKSIZE)
    #print("Parameters in CALL MSXPI:",data)
    
    #print("Extracting only ascii bytes and setting reponse...")
    buf1 = data.decode().split("\x00")[0]

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
    print('chatgpt')
    model_engine = "text-davinci-003"
    
    rc,data = recvdata(BLKSIZE)
    query = data.decode().split("\x00")[0]

    if len(getMSXPiVar('OPENAIKEY')) == 0:
        print("chatagpt: no key - exiting")
        sendmultiblock('Pi:Error - OPENAIKEY is not defined. Define your key with PSET'.encode(), BLKSIZE, RC_FAILED)
        return RC_SUCCESS
        
    openai.api_key = getMSXPiVar('OPENAIKEY')
    
    if rc == RC_SUCCESS:
        if 1==1: #try:
            response = openai.Completion.create(
                engine=model_engine,
                prompt=query,
                max_tokens=1024,
                temperature=0.5,
            )
   
            #print("Response:",response)
            buf = response['choices'][0]['text']
            sendmultiblock(buf.encode(), BLKSIZE, RC_SUCCESS)
        #except Exception as e:
        #    print("Pi:Error - ",str(e).encode())
        #    sendmultiblock(("Pi:Error - "+str(e)).encode(), BLKSIZE, RC_FAILED)
    else:
        sendmultiblock('Pi:Error'.encode(), BLKSIZE, rc)
        
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
           ['DriveM','ftp://192.168.1.100'], \
           ['DriveR1','http://www.msxarchive.nl/pub/msx/games/roms/msx1'], \
           ['DriveR2','http://www.msxarchive.nl/pub/msx/games/roms/msx2'], \
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
           ['OPENAIKEY',''], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free']]

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

init_spi_bitbang()
GPIO.output(RPI_READY, GPIO.LOW)
print("GPIO Initialized\n")

print("Starting MSXPi Server Version ",version,"Build",BuildId)

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
    GPIO.cleanup() # cleanup all GPIO
    print("Terminating msxpi-server")
