#!/usr/bin/python3
# External module imports
import RPi.GPIO as GPIO
import time
import subprocess
from urllib.request import urlopen
import mmap
import fcntl,os
import sys
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

version = "1.1"
BuildId = "20230408.531"

CMDSIZE = 3 + 9
MSGSIZE = 3 + 128
BLKSIZE = 3 + 256
SECTORSIZE = 3 + 512

# Pin Definitons
csPin   = 21
sclkPin = 20
mosiPin = 16
misoPin = 12
rdyPin  = 25

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

MSXPIHOME = "/home/msxpi"
RAMDISK = "/media/ramdisk"
TMPFILE = RAMDISK + "/msxpi.tmp"

def init_spi_bitbang():
# Pin Setup:
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(csPin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(sclkPin, GPIO.OUT)
    GPIO.setup(mosiPin, GPIO.IN)
    GPIO.setup(misoPin, GPIO.OUT)
    GPIO.setup(rdyPin, GPIO.OUT)

def tick_sclk():
    GPIO.output(sclkPin, GPIO.HIGH)
    #time.sleep(SPI_SCLK_HIGH_TIME)
    GPIO.output(sclkPin, GPIO.LOW)
    #time.sleep(SPI_SCLK_LOW_TIME)

def SPI_MASTER_transfer_byte(byte_out):
    #print "transfer_byte:sending",hex(byte_out)
    byte_in = 0
    tick_sclk()
    for bit in [0x80,0x40,0x20,0x10,0x8,0x4,0x2,0x1]:
        #print(".")
        if (int(byte_out) & bit):
            GPIO.output(misoPin, GPIO.HIGH)
        else:
            GPIO.output(misoPin, GPIO.LOW)

        GPIO.output(sclkPin, GPIO.HIGH)
        #time.sleep(SPI_SCLK_HIGH_TIME)
        
        if GPIO.input(mosiPin):
            byte_in |= bit
    
        GPIO.output(sclkPin, GPIO.LOW)
        #time.sleep(SPI_SCLK_LOW_TIME)

    tick_sclk()
    #print "transfer_byte:received",hex(byte_in),":",chr(byte_in)
    return byte_in

def piexchangebyte(byte_out=0):
    rc = RC_SUCCESS
    
    GPIO.output(rdyPin, GPIO.HIGH)
    while(GPIO.input(csPin)):
        pass

    byte_in = SPI_MASTER_transfer_byte(byte_out)
    GPIO.output(rdyPin, GPIO.LOW)

    #print "piexchangebyte: received:",hex(mymsxbyte)
    return byte_in

def piexchangebytewithtimeout(byte_out=0,twait=5):
    rc = RC_SUCCESS
    
    t0 = time.time()
    GPIO.output(rdyPin, GPIO.HIGH)
    while((GPIO.input(csPin)) and (time.time() - t0) < twait):
        pass

    t1 = time.time()

    if ((t1 - t0) > twait):
        return ABORT

    byte_in = SPI_MASTER_transfer_byte(byte_out)
    GPIO.output(rdyPin, GPIO.LOW)

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
                
def getpath(basepath, path):

    path=path.strip().rstrip(' \t\n\0')
    if  path.startswith('/'):
        urltype = 0 # this is an absolute local path
        newpath = path
    elif (path.startswith('m:') or \
        path.startswith('ma1:') or \
        path.startswith('ma2:') or \
        path.startswith('http') or \
        path.startswith('ftp') or \
        path.startswith('nfs') or \
        path.startswith('smb')):
        urltype = 2 # this is an absolute network path
        newpath = path
    elif basepath.startswith('/'):
        urltype = 1 # this is an relative local path
        newpath = basepath + "/" + path
    elif (basepath.startswith('m:') or \
        basepath.startswith('ma1:') or \
        basepath.startswith('ma2:') or \
        basepath.startswith('http') or \
        basepath.startswith('ftp') or \
        basepath.startswith('nfs') or \
        basepath.startswith('smb')):
        urltype = 3 # this is an relative network path
        newpath = basepath + "/" + path
       
    return [urltype, newpath]

def msxdos_inihrd(filename, access=mmap.ACCESS_WRITE):
    print("msxdos_inihrd")
    
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
    
    rc = sendmultiblock(buf, BLKSIZE, False, RC_SUCCESS)
    
    #print("ini_fcb: Exiting")
    
    return rc

def prun(cmd = ''):
    print("prun")
    rc = RC_SUCCESS
    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        rc,data = recvdata()
        
        if data[0] == 0:
            cmd=''
        else:
            cmd = data.decode().split("\x00")[0]
    
    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        rc = RC_FAILED
        sendmultiblock("Syntax: prun <command> <::> command. To  pipe a command to other, use :: instead of |".encode(),BLKSIZE,True,rc)
    else:
        cmd = cmd.replace('::','|')
        try:
            p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
            buf = p.stdout.read().decode()
            err = (p.stderr.read().decode())
            if len(err) > 0 or len(buf) == 0:
                rc = RC_FAILED
                sendmultiblock(str(err).encode(),BLKSIZE,True,rc)
                return rc

            sendmultiblock(buf.encode(), BLKSIZE, True, RC_SUCCESS)

        except Exception as e:
            print("prun: exception")
            rc = RC_FAILED
            sendmultiblock("Pi:Error - "+str(e)+'\n'.encode(),BLKSIZE, True, rc)

    #print(hex(rc))
    return rc

def pdir():
    global psetvar
    basepath = psetvar[0][1]
    rc = RC_SUCCESS
    print("pdir")

    rc,data = recvdata(BLKSIZE)

    if data[0] == 0:
        path=''
    else:
        path = data.decode().split("\x00")[0]
        
    try:
        urlcheck = getpath(basepath, path)
        if (urlcheck[0] == 0 or urlcheck[0] == 1):
            if (path.strip() == '*'):
                prun('ls -l ' + urlcheck[1])
            elif ('*' in path):
                numChilds = path.count('/')
                fileDesc = path.rsplit('/', 1)[numChilds].replace('*','')
                if (fileDesc == '' or len(fileDesc) == 0):
                    fileDesc = '.'
                prun('ls -l ' + urlcheck[1].rsplit('/', 1)[0] + '/|/bin/grep '+ fileDesc)
            else:
                prun('ls -l ' + urlcheck[1])
        else:
            parser = MyHTMLParser()
            try:
                htmldata = urlopen(urlcheck[1]).read().decode()
                parser = MyHTMLParser()
                parser.feed(htmldata)
                buf = " ".join(parser.HTMLDATA)
                rc = sendmultiblock(buf.encode(),BLKSIZE, True, RC_SUCCESS)

            except Exception as e:
                rc = RC_FAILED
                sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, True, RC_SUCCESS)

    except Exception as e:
        sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, True, RC_SUCCESS)

    #print("pdir:exiting rc:",hex(rc))
    return rc

def pcd():    
    rc = RC_SUCCESS
    global psetvar
    basepath = psetvar[0][1]
    newpath = basepath
    
    #print("pcd: system path:",basepath)
    rc,data = recvdata()

    if data[0] == 0:
        path=''
    else:
        path = data.decode().split("\x00")[0]
        
    try:
        if (1 == 1):
            if (len(path) == 0 or path == '' or path.strip() == "."):
                sendmultiblock(basepath.encode(), BLKSIZE, True, RC_SUCCESS)
            elif (path.strip() == ".."):
                newpath = basepath.rsplit('/', 1)[0]
                if (newpath == ''):
                    newpath = '/'
                psetvar[0][1] = newpath
                sendmultiblock(str(newpath).encode(), BLKSIZE, True, RC_SUCCESS)
            else:
                #print "pcd:calling getpath"
                urlcheck = getpath(basepath, path)
                newpath = urlcheck[1]

                if (newpath[:2].lower() == "m:"):
                    rc = RC_SUCCESS
                    psetvar[0][1] = 'ftp://192.168.1.100/'
                    sendmultiblock(str(psetvar[0][1]).encode(), BLKSIZE, True, rc)
                elif (newpath[:4].lower() == "ma1:"):
                    rc = RC_SUCCESS
                    psetvar[0][1] = 'http://www.msxarchive.nl/pub/msx/games/roms/msx1/'
                    sendmultiblock(str(psetvar[0][1]).encode(), BLKSIZE, True, rc)
                elif  (newpath[:4].lower() == "ma2:"):
                    rc = RC_SUCCESS
                    psetvar[0][1] = 'http://www.msxarchive.nl/pub/msx/games/roms/msx2/'
                    sendmultiblock(str(psetvar[0][1]).encode(), BLKSIZE, True, rc)
                elif (newpath[:4].lower() == "http" or \
                    newpath[:3].lower() == "ftp" or \
                    newpath[:3].lower() == "nfs" or \
                    newpath[:3].lower() == "smb"):
                    rc = RC_SUCCESS
                    psetvar[0][1] = newpath
                    sendmultiblock(str(newpath+'\n').encode(), BLKSIZE, True, rc)
                else:
                    if (os.path.isdir(newpath)):
                        psetvar[0][1] = newpath
                        sendmultiblock(str(newpath).encode(), BLKSIZE, True, RC_SUCCESS)
                    elif (os.path.isfile(str(newpath))):
                        sendmultiblock("Pi:Error - not a folder".encode(), BLKSIZE, True, RC_FAILED)
                    else:
                        sendmultiblock("Pi:Error - path not found".encode(), BLKSIZE, True, RC_FAILED)
        else:
            rc = RC_FAILNOSTD
            print("pcd:out of sync in RC_WAIT")
    except Exception as e:
        print("pcd:"+str(e))
        sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, True, RC_FAILED)

    return [rc, newpath]
    
def pcopy():

    buf = bytearray(BLKSIZE)
    rc = RC_SUCCESS

    global psetvar,GLOBALRETRIES
    basepath = psetvar[0][1]
    
    # Receive parameters -
    rc,data = recvdata(BLKSIZE)
    
    if data[0] == 0:
        path=''
    else:
        path = data.decode().split("\x00")[0]
        
    path = path.strip().split()
                   
    if (len(path) == 0 or path[0].lower() == ('/h')):
        buf = 'Syntax:\n'
        buf = buf + 'pcopy remotefile <localfile>\n'
        buf = buf +'Valid devices:\n'
        buf = buf +'/, path, http, ftp, nfs, smb\n'
        buf = buf + 'Path relative to RPi path (set with pcd)'
        rc = sendmultiblock(buf.encode(), BLKSIZE, True, RC_FAILED)
        return rc

    if (path[0].lower() == '/z'):
        expand = True
        path = path[1:]
    else:
        expand = False

    if len(path) < 1:
        rc = sendmultiblock("Pi:Error - Missing file name".encode(), BLKSIZE, True, RC_FAILED)
        return rc

    if (path[0].lower().startswith('m:')):
        basepath = 'ftp://192.168.1.100/'
        fname1 = basepath + path[0].split(':')[1]
    elif (path[0].lower().startswith('ma1:')):
        basepath = 'http://www.msxarchive.nl/pub/msx/games/roms/msx1/'
        fname1 = basepath + path[0].split(':')[1]
        if expand == True:
            if len(path) > 1:
                fname2 = path[1]
            else:
                fname2 = '-'
        elif len(path) > 1:
            fname2 = path[1]
        else:
            fname0 = fname1.split('/')
            fname2 = fname0[len(fname0)-1]
    elif  (path[0].lower().startswith('ma2:')):
        basepath = 'http://www.msxarchive.nl/pub/msx/games/roms/msx2/'
        fname1 = basepath + path[0].split(':')[1]
    elif (path[0].lower().startswith('http') or \
        path[0].lower().startswith('ftp') or \
        path[0].lower().startswith('nfs') or \
        path[0].lower().startswith('smb')):
        fname1 = path[0]
    elif (path[0].startswith('/')):
        fname1 = path[0]
    else:
        fname1 = basepath + '/' + path[0]

    if expand == True:
        if len(path) > 1:
            fname2 = path[1]
        else:
            fname2 = '-'
    elif len(path) > 1:
        fname2 = path[1]
    else:
        fname0 = fname1.split('/')
        fname2 = fname0[len(fname0)-1]

    urlcheck = getpath(basepath, fname1)
    # basepath 0 local filesystem
    if (urlcheck[0] == 0 or urlcheck[0] == 1):
        
        try:
            with open(fname1, mode='rb') as f:
                buf = f.read()

            filesize = len(buf)
 
        except Exception as e:
            err = 'Pi:Error - ' + str(e)
            rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, True, RC_FAILED)
            return RC_FAILED

    else:

        try:
            urlhandler = urlopen(fname1)
            buf = urlhandler.read()
            filesize = len(buf)
                    
        except Exception as e:
            rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, True, RC_FAILED)
            return RC_FAILED

    if rc == RC_SUCCESS:
        # if /z passed, will uncompress the file
        if expand:
            tmpfn0 = fname1.split('/')
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
                if fname2 == '-':
                    fname2 = fname1
                fname1 = '/tmp/msxpi/' + fname1

                try:
                    with open(fname1, mode='rb') as f:
                        buf = f.read()

                    filesize = len(buf)
                    rc = RC_SUCCESS
                    
                except Exception as e:
                    rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, True, RC_FAILED)
                    return RC_FAILED
       
            else:
                rc = sendmultiblock(('Pi:Error - ' + perror).encode(), BLKSIZE, True, RC_FAILED)
                return RC_FAILED
                
    if rc == RC_SUCCESS:
        if filesize == 0:
            rc = sendmultiblock("Pi:Error - File size is zero bytes".encode(), BLKSIZE, True, RC_FAILED)
            return RC_FAILED

        else:
            if not msxdos1boot: # Boot was not from MSXPi disk drive
                rc = ini_fcb(fname2,filesize)
                if rc != RC_SUCCESS:
                    print("pcopy: ini_fcb failed")
                    return rc
                # This will send the file to MSX, for pcopy to write it to disk
                rc = sendmultiblock(buf,SECTORSIZE, False, rc)
            
            else:# Booted from MSXPi disk drive (disk images)
                # this routine will write the file directly to the disk image in RPi
                try:
                    fatfsfname = "fat:///"+psetvar[1][1]        # Asumme Drive A:
                    if fname2.upper().startswith("A:"):
                        fname2 = fname2.split(":")
                        if len(fname2[1]) > 0:
                            fname2=fname2[1]           # Remove "A:" from name
                        else:
                            fname2=fname1.split("/")[len(fname1.split("/"))-1]           # Drive not passed in name
                    elif fname2.upper().startswith("B:"):
                        fatfsfname = "fat:///"+psetvar[2][1]    # Is Drive B:
                        fname2 = fname2.split(":")
                        if len(fname2[1]) > 0:
                            fname2=fname2[1]           # Remove "B:" from name
                        else:
                            fname2=fname1.split("/")[len(fname1.split("/"))-1]           # Drive not passed in name
                    dskobj = open_fs(fatfsfname)
                    dskobj.create(fname2,True)
                    dskobj.writebytes(fname2,buf)
                    sendmultiblock("Pi:Ok\n".encode(), BLKSIZE, True, RC_TERMINATE)
                except Exception as e:
                    rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, True, RC_FAILED)
            
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
    
    sendmultiblock(pdate, CMDSIZE, False, RC_SUCCESS)
   
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
    
    if data[0] == 0:
        cmd=''
    else:
        cmd = data.decode().split("\x00")[0]
    
    rc = prun("/home/pi/msxpi/pplay.sh pplay.sh " +  psetvar[0][1]+ " "+cmd)
    
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
    
def pset():

    global psetvar,drive0Data,drive1Data
    
    rc,data = recvdata(BLKSIZE)

    if data[0] == 0:
        cmd=''
    else:
        cmd = data.decode().split("\x00")[0]
        
    if  (cmd.lower() == "/h" or cmd.lower() == "/help"):
        rc = sendmultiblock("Syntax:\npset                    Display variables\npset varname varvalue   Set varname to varvalue\npset varname            Delete variable varname".encode(), BLKSIZE, True, RC_FAILED)
        return rc
    elif (len(cmd) == 0):   # Display current parameters
        s = str(psetvar)
        buf = s.replace(", ",",").replace("[[","").replace("]]","").replace("],","\n").replace("[","").replace(",","=").replace("'","")
        rc = sendmultiblock(buf.encode(), BLKSIZE, True, RC_SUCCESS)
        return rc
        
    # Set a new parameter or update an existing parameter
    rc = RC_FAILED 
    cmd=cmd.split(" ")
    
    for index in range(0,len(psetvar)):

        if (psetvar[index][0] == str(cmd[0])):
            
            if len(cmd) == 1:  #will erase / clean a variable
                psetvar[index][0] = 'free'
                psetvar[index][1] = 'free'
                rc = sendmultiblock("Pi:Ok\n".encode(), BLKSIZE, True, RC_SUCCESS)
                return RC_SUCCESS    
                         
            else:
                
                try:
                    
                    if str(cmd[0]) == 'DRIVE0':
                        rc,drive0Data = msxdos_inihrd(cmd[1])
                        psetvar[index][1] = str(cmd[1])
                        rc = sendmultiblock("Pi:Ok\n".encode(), BLKSIZE, True, RC_SUCCESS)
                        return RC_SUCCESS

                    elif str(cmd[0]) == 'DRIVE1':
                        rc,drive1Data = msxdos_inihrd(cmd[1])
                        psetvar[index][1] = str(cmd[1])    
                        rc = sendmultiblock("Pi:Ok\n".encode(), BLKSIZE, True, RC_SUCCESS)
                        return RC_SUCCESS
                    else: 
                        psetvar[index][1] = str(cmd[1])    
                        rc = sendmultiblock("Pi:Ok\n".encode(), BLKSIZE, True, RC_SUCCESS)
                        return RC_SUCCESS
                        
                except Exception as e:
                    
                    rc = sendmultiblock(('Pi:Error - ' + str(e)).encode(), BLKSIZE, True, RC_FAILED)
                    return RC_FAILED
                    
    # Check if there is a slot, then add new parameter
    for index in range(7,len(psetvar)):

        if (psetvar[index][0] == "free" and psetvar[index][0] != str(cmd[0])):
            psetvar[index][0] = str(cmd[0])
            psetvar[index][1] = str(cmd[1])
            rc = RC_SUCCESS
            break

    if rc == RC_SUCCESS:
        rc = sendmultiblock("Pi:Ok\n".encode(), BLKSIZE, True, RC_SUCCESS)
    else:        
        rc = sendmultiblock("Pi:Error setting parameter".encode(), BLKSIZE, True, RC_FAILED)
    
    #print(hex(rc))
    return rc
                            
def pwifi():

    global psetvar
    wifissid = psetvar[4][1]
    wifipass = psetvar[5][1]

    rc,data = recvdata()

    if data[0] == 0:
        parms=''
    else:
        parms = data.decode().split("\x00")[0]

    cmd=parms.strip()

    if (cmd[:2] == "/h"):
        sendmultiblock("Pi:Usage:\npwifi display | set".encode(), BLKSIZE, True, RC_FAILED)
        return RC_SUCCESS

    if (cmd[:1] == "s" or cmd[:1] == "S"):
        buf = "country=GB\n\nctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\nupdate_config=1\nnetwork={\n"
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
    rc = sendmultiblock(ver.encode(), BLKSIZE, True, RC_SUCCESS)
    return rc
    
def irc():

    global allchann,psetvar,channel,ircsock
    ircserver = psetvar[8][1]
    ircport = int(psetvar[9][1])
    msxpinick =  psetvar[7][1]
    
    rc,data = recvdata()
    if rc != RC_SUCCESS:
        return rc
        
    if data[0] == 0:
        cmd=''
    else:
        cmd = data.decode().split("\x00")[0].lower()
    
    rc = RC_SUCCNOSTD
    
    if 1==1:#try:
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
            ircmsg = 'Connected to '+psetvar[8][1]
            sendmultiblock(ircmsg.encode(), BLKSIZE, True, RC_SUCCESS)
        elif cmd[:3] == "msg":
            ircsock.setblocking(0);
            ircsock.send(("PRIVMSG "+cmd[4:] +"\r\n").encode())
            sendmultiblock("Pi:Ok\n".encode(), BLKSIZE, True, RC_SUCCNOSTD)
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
            sendmultiblock(ircmsg.encode(), BLKSIZE, True, rc)

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
    
            sendmultiblock(ircmsg.encode(), BLKSIZE, True, rc)
            
        elif cmd[:5] == 'names':
            print("names:",cmd)
            ircsock.send((cmd+"\r\n").encode())
            ircmsg = ''
            ircmsg = ircmsg + ircsock.recv(2048).decode("UTF-8")
            ircmsg = ircmsg.strip('\n\r')
            print("names:",ircmsg)
            ircmsg = "Users on channel " #+ ircmsg.split('=',1)[1]
            sendmultiblock(ircmsg.encode(), BLKSIZE, True, RC_SUCCESS)
        elif cmd[:4] == 'quit':
            ircsock.send(("/quit\r\n").encode())
            ircsock.close()
            sendmultiblock("Pi:leaving room\r\n".encode(),BLKSIZE, True, RC_SUCCESS)
        elif cmd[:4] == 'part':
            print("part:")
            ircsock.send(("/part\r\n").encode())
            ircsock.close()
            sendmultiblock("Pi:leaving room\n".encode(),BLKSIZE, True, RC_SUCCESS)
        else:
            print("irc:no valid command received")
            sendmultiblock("Pi:No valid command received".encode(),BLKSIZE, True, rc)
    #except Exception as e:
    #        print("irc:Caught exception"+str(e))
    #        sendmultiblock("Pi:"+str(e).encode(), BLKSIZE, True, rc)
            
def dosinit():
    
    global msxdos1boot
        
    rc,data = recvdata(CMDSIZE)
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
    rc , drive0Data = msxdos_inihrd(psetvar[1][1])
    rc , drive1Data = msxdos_inihrd(psetvar[2][1])

def dskiords():
    print("dskiords")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data
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
        rc = senddata(buf,SECTORSIZE)
        sectorcnt += 1
        
        if  rc == RC_SUCCESS:
            pass
            #print("dskiords: checksum is a match")
        else:
            print("dskiords: checksum error")
            break
 
def dskiowrs():
    print("dskiowrs")
    
    global msxdos1boot,sectorInfo,drive0Data,drive1Data
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
        rc,buf = recvdata(SECTORSIZE)
        if  rc == RC_SUCCESS:
            print("dskiowrs: checksum is a match")
            if sectorInfo[0] == 0:
                drive0Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = buf
            else:
                drive1Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = buf
            sectorcnt += 1
        else:
            print("dskiowrs: checksum error")
            break
                  
def dskiosct():
    print("dskiosct")
    
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
            break
        else:
            rc = RC_TXERROR
            print("recvdata: checksum error")

    #print (hex(rc))
    return rc,data

def senddata(data, blocksize = BLKSIZE):
    
    print("senddata")

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
            break
        else:
            rc = RC_TXERROR
            print("senddata: checksum error")

    #print (hex(rc))
    return rc

def sendmultiblock(buf, blocksize = BLKSIZE, sendheader = False, rc = RC_SUCCESS):

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

def template():
    print("template now receiving parameters...")
    
    # Parameters have always a fixed size: BLKSIZE
    rc,data = recvdata(BLKSIZE)    
    print("Raw data received:",data)
    
    print("Extracting only ascii bytes and setting reponse...")
    buf = 'MSXPi received: ' + data.decode().split("\x00")[0]
    
    print("Sending response: ",buf) 
    rc = sendmultiblock(buf.encode(), BLKSIZE, True, RC_SUCCESS)
        
""" ============================================================================
    msxpi-server.py
    main program starts here
    ============================================================================
"""

psetvar = [['PATH','/home/pi/msxpi'], \
           ['DRIVE0','/home/pi/msxpi/disks/msxpiboot.dsk'], \
           ['DRIVE1','/home/pi/msxpi/disks/tools.dsk'], \
           ['WIDTH','80'], \
           ['WIFISSID','MYWIFI'], \
           ['WIFIPWD','MYWFIPASSWORD'], \
           ['DSKTMPL','disks/msxpi_720KB_template.dsk'], \
           ['IRCNICK','msxpi'], \
           ['IRCADDR','chat.freenode.net'], \
           ['IRCPORT','6667'], \
           ['WUPPH','351966764458'], \
           ['WUPPW','D4YQDfsnY3KIgW4azGdtYDbMAO4='], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ['free','free'], \
           ]

# irc
channel = "#msxpi"
allchann = []
ircsock = None
errcount = 0
msxdos1boot = False
    
init_spi_bitbang()
GPIO.output(rdyPin, GPIO.LOW)
print("GPIO Initialized\n")
print("Starting MSXPi Server Version ",version,"Build",BuildId)

if 1==1: #try:
    while True:
        if 1==1: #try:
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
        #except Exception as e:
        #    errcount += 1
        #    print(str(e))
        #    recvdata(BLKSIZE)       # Read & discard parameters to avoid sync errors
        #    sendmultiblock("Pi:Error - "+str(e),BLKSIZE, True, RC_FAILED)

#except KeyboardInterrupt:
#    GPIO.cleanup() # cleanup all GPIO
#    print("Terminating msxpi-server")
