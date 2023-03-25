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

version = "1.1"
BuildId = "20230325.006"

CMDSIZE = 9
MSGSIZE = 128
BLKSIZE = 256
SECTORSIZE = 512

# Pin Definitons
csPin   = 21
sclkPin = 20
mosiPin = 16
misoPin = 12
rdyPin  = 25

SPI_SCLK_LOW_TIME = 0.001
SPI_SCLK_HIGH_TIME = 0.001

GLOBALRETRIES       = 100
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
RC_CRCERROR         =    0xE2
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
RC_ESCAPE           =    0xED
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
    GPIO.setup(mosiPin, GPIO.IN,pull_up_down=GPIO.PUD_UP)
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

    path=path.strip().rstrip(' \t\r\n\0')
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

    lastSectorSize = fsize % SECTORSIZE
    if lastSectorSize == 0:
        lastSectorSize = SECTORSIZE
        
    numblocks = math.ceil(fsize / SECTORSIZE)
    if numblocks == 0:
        numblocks = 1
    
    #print("Drive, Filename, N# blocks:",msxdrive,msxfcbfname,numblocks)

    # send FCB structure to MSX
    buf = bytearray()
    buf.extend(RC_SUCCESS.to_bytes(1,'little'))
    buf.extend((numblocks % 256).to_bytes(1,'little'))
    buf.extend((numblocks // 256).to_bytes(1,'little'))
    buf.extend((lastSectorSize % 256).to_bytes(1,'little'))
    buf.extend((lastSectorSize // 256).to_bytes(1,'little'))
    buf.extend(msxdrive.to_bytes(1,'little'))
    buf.extend(msxfcbfname.encode())
    
    rc = sendmultiblock(buf, MSGSIZE)
    
    #print("ini_fcb: Exiting")
    
    return rc

def prun(cmd = ''):

    rc = RC_SUCCESS

    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        rc,data = recvdata()
        cmd = data.decode().split("\x00")[0]
    
    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        #print("prun if:syntax error")
        sendmultiblock("Syntax: prun <command> <::> command. To  pipe a command to other, use :: instead of |")
        rc = RC_FAILED
    else:
        #print("prun else")
        cmd = cmd.replace('::','|')
        try:
            #print("prun: inside try: cmd = ",cmd)
            p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
            buf = p.stdout.read().decode()
            err = (p.stderr.read().decode())
            if len(err) > 0 or len(buf) == 0:
                sendmultiblock(str(err),BLKSIZE)
                return RC_FAILED

            sendmultiblock(buf, BLKSIZE)

        except Exception as e:
            print("prun: exception")
            rc = RC_FAILED
            sendmultiblock("Pi:"+str(e)+'\n',BLKSIZE)

    #print(hex(rc))
    return rc

def pdir():
    global psetvar
    basepath = psetvar[0][1]
    rc = RC_SUCCESS
    #print "pdir:starting"

    rc,data = recvdata()
    path = data.decode().split("\x00")[0]
    
    try:
        if (1 == 1):
            #print("pdir: if1")
            urlcheck = getpath(basepath, path)
            if (urlcheck[0] == 0 or urlcheck[0] == 1):
                #print("pdir: if2")
                if (path.strip() == '*'):
                    prun('ls -l ' + urlcheck[1])
                elif ('*' in path):
                    #print("pdir: elif1")
                    numChilds = path.count('/')
                    fileDesc = path.rsplit('/', 1)[numChilds].replace('*','')
                    if (fileDesc == '' or len(fileDesc) == 0):
                        fileDesc = '.'
                    prun('ls -l ' + urlcheck[1].rsplit('/', 1)[0] + '/|/bin/grep '+ fileDesc)
                else:
                    #print("pdir: else inside",urlcheck[1])
                    prun('ls -l ' + urlcheck[1])
            else:
                #print("pdir: else out")
                parser = MyHTMLParser()
                try:
                    htmldata = urlopen(urlcheck[1]).read().decode()
                    parser = MyHTMLParser()
                    parser.feed(htmldata)
                    buf = " ".join(parser.HTMLDATA)
                    rc = sendmultiblock(buf)

                except Exception as e:
                    rc = RC_FAILED
                    print("pdir exception 1:http error "+ str(e))
                    sendmultiblock(str(e))
        else:
            rc = RC_FAILNOSTD
            print("pdir:out of sync in RC_WAIT")
    except Exception as e:
        #print("pdir exception 2:"+str(e))
        sendmultiblock('Pi:'+str(e))

    #print("pdir:exiting rc:",hex(rc))
    return rc

def pcd():    
    rc = RC_SUCCESS
    global psetvar
    basepath = psetvar[0][1]
    newpath = basepath
    
    #print("pcd: system path:",basepath)
    rc,data = recvdata()
    path = data.decode().split("\x00")[0]

    try:
        if (1 == 1):
            if (len(path) == 0 or path == '' or path.strip() == "."):
                sendmultiblock(basepath)
            elif (path.strip() == ".."):
                newpath = basepath.rsplit('/', 1)[0]
                if (newpath == ''):
                    newpath = '/'
                psetvar[0][1] = newpath
                sendmultiblock(str(newpath))
            else:
                #print "pcd:calling getpath"
                urlcheck = getpath(basepath, path)
                newpath = urlcheck[1]

                print(newpath)
                
                if (newpath[:2] == "m:"):
                    rc = RC_SUCCESS
                    psetvar[0][1] = 'ftp://192.168.1.100/'
                    sendmultiblock(str(psetvar[0][1] +'\n'))
                elif (newpath[:4] == "ma1:"):
                    rc = RC_SUCCESS
                    psetvar[0][1] = 'http://www.msxarchive.nl/pub/msx/games/roms/msx1/'
                    sendmultiblock(str(psetvar[0][1] +'\n'))
                elif  (newpath[:4] == "ma2:"):
                    rc = RC_SUCCESS
                    psetvar[0][1] = 'http://www.msxarchive.nl/pub/msx/games/roms/msx2/'
                    sendmultiblock(str(psetvar[0][1] +'\n'))
                elif (newpath[:4] == "http" or \
                    newpath[:3] == "ftp" or \
                    newpath[:3] == "nfs" or \
                    newpath[:3] == "smb"):
                    rc = RC_SUCCESS
                    psetvar[0][1] = newpath
                    sendmultiblock(str(newpath+'\n'))
                else:
                    newpath = str(newpath)
                    if (os.path.isdir(newpath)):
                        psetvar[0][1] = newpath
                        sendmultiblock(newpath+'\n')
                    elif (os.path.isfile(str(newpath))):
                        sendmultiblock("Pi:Error - not a folder")
                    else:
                        sendmultiblock("Pi:Error - path not found")
        else:
            rc = RC_FAILNOSTD
            print("pcd:out of sync in RC_WAIT")
    except Exception as e:
        print("pcd:"+str(e))
        sendmultiblock('Pi:'+str(e))

    return [rc, newpath]

def pcopy():

    inifcb=True
    buf = bytearray(BLKSIZE)
    rc = RC_SUCCESS

    global psetvar,GLOBALRETRIES
    basepath = psetvar[0][1]
    
    # Receive parameters -
    rc,data = recvdata(BLKSIZE)
    path = data.decode().split("\x00")[0]
    
    print("pcopy: Starting with params ",path)

    path = path.strip().split()
                   
    if (len(path) == 0 or path[0].lower().startswith('/h') ):
        buf = 'Syntax:\n'
        buf = buf + 'pcopy remotefile <localfile>\n'
        buf = buf +'Valid devices:\n'
        buf = buf +'/, path, http, ftp, nfs, smb\n'
        buf = buf + 'Path relative to RPi path (set with pcd)'    
        #print(len(buf),buf)
        rc = send_rc_msg(RC_FAILED,buf)
        return rc

    if (path[0].lower() == '/z'):
        expand = True
        path = path[1:]
    else:
        expand = False
    
    print(len(path))
    if len(path) < 1:
            rc = send_rc_msg(RC_FAILED,"Pi:File name missing")
            return rc
    elif len(path) == 1:
        fname1 = path[0]
        fname_msx = ''
    elif len(path) == 2:
        fname1 = path[0]
        fname_msx = path[1]
    
    print(fname1)
    print(basepath)
    
    if (fname1.startswith('m:')):
        basepath = 'ftp://192.168.1.100/'
        fileinfo = basepath + fname1.split(':')[1]
        fname1 = fname1.split(':')[1]
        if len(fname_msx) == 0:
            fname_msx = fname1
    elif (fname1.startswith('ma1:')):
        basepath = 'http://www.msxarchive.nl/pub/msx/games/roms/msx1/'
        fileinfo = basepath + fname1.split(':')[1]
        fname1 = fname1.split(':')[1]
        if len(fname_msx) == 0:
            fname_msx = fname1
    elif  (fname1.startswith('ma2:')):
        basepath = 'http://www.msxarchive.nl/pub/msx/games/roms/msx2/'
        fileinfo = basepath + fname1.split(':')[1]    
        fname1 = fname1.split(':')[1]
        if len(fname_msx) == 0:
            fname_msx = fname1
    elif (fname1.startswith('http') or \
        fname1.startswith('ftp') or \
        fname1.startswith('nfs') or \
        fname1.startswith('smb') or \
        fname1.startswith('/')):
        fileinfo = fname1
        if len(fname_msx) == 0:
            fname_msx0 = fname1.split('/')
            fname_msx = fname_msx0[len(fname_msx0)-1]
    elif fname1 == '':
        fileinfo = basepath
        fname_msx = fname1
    else: 
        if len(fname_msx) == 0:
            fname_msx = fname1
            fileinfo = basepath+'/'+fname1
                            
    fname_rpi = fileinfo
        
    urlcheck = getpath(basepath, fname1)
    # basepath 0 local filesystem
    if (urlcheck[0] == 0 or urlcheck[0] == 1):
        print("pcopy: path is local:",fname_rpi,fname_msx)
        
        try:
            with open(fname_rpi, mode='rb') as f:
                buf = f.read()

            filesize = len(buf)
 
        except Exception as e:
            print("pcopy: exception 1",str(e))
            send_rc_msg(RC_FAILED,str(e))
            return RC_FAILED

    else:
        print("pcopy: path is remote:",fname_rpi,fname_msx)
        try:
            urlhandler = urlopen(fname_rpi)
            buf = urlhandler.read()
            filesize = len(buf)
                    
            # if /z passed, will uncompress the file
            if expand:
                #print("Entered expand")
                os.system('rm /tmp/msxpi/* 2>/dev/null')
                tmpfile = open('/tmp/' + fname1, 'wb')
                tmpfile.write(buf)
                tmpfile.close()
                if ".lzh" in fname1:
                    rc = os.system('/usr/bin/lhasa -xfiw=/tmp/msxpi /tmp/' + fname1)
                else:
                    rc = os.system('/usr/bin/unar -f -o /tmp/msxpi /tmp/' + fname1)
                    
                if rc == 0:
                    #print("entered rc == 0")
                    fname_rpi = os.listdir('/tmp/msxpi')[0]
                    if fname_msx == '':
                        fname_msx = fname_rpi
                    fname_rpi = '/tmp/msxpi/' + fname_rpi

                    try:
                        with open(fname_rpi, mode='rb') as f:
                            buf = f.read()

                        filesize = len(buf)
                        rc = RC_SUCCESS
                        
                    except Exception as e:
                        print("pcopy: exception 2",str(e))
                        send_rc_msg(RC_FAILED,str(e))
                        return RC_FAILED
       
                else:
                    send_rc_msg(RC_FAILED,"Pi:Error decompressing the file")
                    return RC_FAILED
    
        except Exception as e:
            send_rc_msg(RC_FAILED,str(e))
            return RC_FAILED

    if rc == RC_SUCCESS:
        #print("pcopy: File open success, target name,size is ",fname_msx,filesize)
        if filesize == 0:
            send_rc_msg(RC_FAILED,"Pi:File size is zero bytes")
            return RC_FAILED

        else:
            if inifcb:
                rc = ini_fcb(fname_msx,filesize)
                if rc != RC_SUCCESS:
                    print("pcopy: ini_fcb failed")
                    return rc
            rc = sendmultiblock(buf,SECTORSIZE)
            
    #print(hex(rc))
    return rc

def ploadr(path=''):
    rc = pcopy(path,False)
    if rc == RC_INVALIDDATASIZE:
        sendmultiblock("Pi:Error - Not valid 8/16/32KB ROM")

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
    
    sendmultiblock(pdate)
   
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
    cmd = data.decode().split("\x00")[0]
    
    rc = prun("/home/pi/msxpi/pplay.sh pplay.sh " +  psetvar[0][1]+ " "+cmd)
    
    #print (hex(rc))
    return rc
    
def pvol():
    rc = RC_SUCCESS
    
    rc,data = recvdata(BLKSIZE)
    vol = data.decode().split("\x00")[0]
    
    rc = prun("mixer set PCM -- "+vol)
    
    print (hex(rc))
    return rc
    
def pset():

    global psetvar,drive0Data,drive1Data
    
    rc,data = recvdata(BLKSIZE)
    cmd = data.decode().split("\x00")[0]

    if  (cmd.lower() == "/h" or cmd.lower() == "/help"):
        rc = sendmultiblock("Syntax:\npset                    Display variables\npset varname varvalue   Set varname to varvalue\npset varname            Delete variable varname", BLKSIZE)
        return rc
    elif (len(cmd) == 0):   # Display current parameters
        s = str(psetvar)
        buf = s.replace(", ",",").replace("[[","").replace("]]","").replace("],","\n").replace("[","").replace(",","=").replace("'","")
        rc = sendmultiblock(buf, BLKSIZE)
        return rc
        
    # Set a new parameter or update an existing parameter
    rc = RC_FAILED 
    cmd=cmd.split(" ")
    
    for index in range(0,len(psetvar)):

        if (psetvar[index][0] == str(cmd[0])):
            
            if len(cmd) == 1:  #will erase / clean a variable
                psetvar[index][0] = 'free'
                psetvar[index][1] = 'free'
                rc = sendmultiblock("Pi:Ok",BLKSIZE)
                return RC_SUCCESS    
                         
            else:
                
                try:
                    
                    if str(cmd[0]) == 'DRIVE0':
                        rc,drive0Data = msxdos_inihrd(cmd[1])
                        psetvar[index][1] = str(cmd[1])
                        rc = sendmultiblock("Pi:Ok",BLKSIZE)
                        return RC_SUCCESS

                    elif str(cmd[0]) == 'DRIVE1':
                        rc,drive1Data = msxdos_inihrd(cmd[1])
                        psetvar[index][1] = str(cmd[1])    
                        rc = sendmultiblock("Pi:Ok",BLKSIZE)
                        return RC_SUCCESS
                        
                except Exception as e:
                    
                    rc = sendmultiblock("Pi:Error - " + str(e),BLKSIZE)
                    return RC_FAILED
                    
    # Check if there is a slot, then add new parameter
    for index in range(7,len(psetvar)):

        if (psetvar[index][0] == "free" and psetvar[index][0] != str(cmd[0])):
            psetvar[index][0] = str(cmd[0])
            psetvar[index][1] = str(cmd[1])
            rc = RC_SUCCESS
            break

    if rc == RC_SUCCESS:
        rc = sendmultiblock("Pi:Ok",BLKSIZE)
    else:        
        rc = sendmultiblock("Pi:Error setting parameter",BLKSIZE)
    
    #print(hex(rc))
    return rc
                            
def pwifi():

    global psetvar
    wifissid = psetvar[4][1]
    wifipass = psetvar[5][1]

    rc,data = recvdata()
    parms = data.decode().split("\x00")[0]
    cmd=parms.strip()

    if (cmd[:2] == "/h"):
        sendmultiblock("Pi:Usage:\npwifi display | set")
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
            prun("sudo ifdown wlan1 && sleep 1 && sudo ifup wlan1")
        else:
            prun("sudo ifdown wlan0 && sleep 1 && sudo ifup wlan0")
    else:
        prun("ip a | grep '^1\\|^2\\|^3\\|^4\\|inet'|grep -v inet6")
    
    return RC_SUCCESS

def pver():
    global version,build
    ver = "MSXPi Server Version "+version+" Build "+build
    rc = sendmultiblock(ver, MSGSIZE)
    return rc
    
def irc(cmd=''):
    piexchangebyte(RC_WAIT)

    global allchann,psetvar,channel,ircsock
    ircserver = psetvar[8][1]
    ircport = int(psetvar[9][1])
    msxpinick =  psetvar[7][1]

    rc = RC_SUCCESS
    cmd = cmd.lower()

    try:
        if cmd[:4] == 'conn':       
            ircsock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            jparm = cmd.split(' ')
            jnick = jparm[1]
            if (jnick == 'none'):
                jnick = msxpinick
            ircsock.connect((ircserver, ircport))
            ircsock.send(bytes("USER "+ jnick +" "+ jnick +" "+ jnick + " " + jnick + "\n"))
            ircsock.send(bytes("NICK "+ jnick +"\n"))
            ircmsg = 'Connected to '+psetvar[8][1]
            sendmultiblock(rc,ircmsg)
        elif cmd[:3] == "msg":
            print("msg:sending msg ",cmd[:4])
            ircsock.send(bytes("PRIVMSG "+ channel +" :" + cmd[4:] +"\n"))
            sendmultiblock(RC_SUCCNOSTD,"Pi:Ok\n")
        elif cmd[:4] == 'join':
            jparm = cmd.split(' ')
            jchannel = jparm[1]
            if jchannel in allchann:
                ircmsg = 'Already joined - setting to current. List of channels:' + str(allchann).replace('bytearray(b','').replace(')','')
                channel = jchannel
            else:
                ircsock.send(bytes("JOIN " + jchannel + "\n"))
                ircmsg = ''
                while (ircmsg.find("End of /NAMES list.") == -1) and \
                      (ircmsg.find("No such channel") == -1) and \
                      (ircmsg.find("Nickname is already in use") == -1):
                    ircmsg = ircmsg + ircsock.recv(2048).decode("UTF-8")
                    ircmsg = ircmsg.strip('\n\r')

                if (ircmsg.find("No such channel") != -1):
                    ircmsg = "No such channel"
                else:
                    ircmsg = ircmsg[ircmsg.find('End of /MOTD command.')+21:]
                    allchann.append(jchannel)
                    channel = jchannel

            sendmultiblock(RC_SUCCESS,ircmsg)

        elif cmd[:4] == 'read':
            ircmsg = 'Pi:Error'
            ircsock.setblocking(0);
            try:
                ircmsg = ircsock.recv(2048)
                ircmsg = ircmsg.strip('\n\r')
                if ircmsg.find("PING :") != -1:
                    ircsock.send(bytes("PONG :ping\n"))
                    ircmsg = 'Pi:Ping\n'
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
                if err == errno.EAGAIN or err == errno.EWOULDBLOCK:
                    ircmsg = 'Pi:no new messages'
                    rc = RC_SUCCNOSTD
                else:
                    print("Socket error")
                    ircmsg = 'Pi:irc Socket error\n'
                    rc = RC_FAILED
  
            ircsock.setblocking(1);
            sendmultiblock(rc,ircmsg)

        elif cmd[:5] == 'names':
            ircsock.send(bytes("NAMES " + channel + "\n"))
            ircmsg = ''
            ircmsg = ircmsg + ircsock.recv(2048).decode("UTF-8")
            ircmsg = ircmsg.strip('\n\r')
            ircmsg = "Users on channel " + ircmsg.split('=',1)[1]
            sendmultiblock(RC_SUCCESS,ircmsg)
        elif cmd[:4] == 'quit':
            ircsock.send(bytes("/quit\n"))
            ircsock.close()
            sendmultiblock(RC_SUCCESS,"Pi:leaving room\n")
        elif cmd[:4] == 'part':
            ircsock.send(bytes("/part\n"))
            ircsock.close()
            sendmultiblock(RC_SUCCESS,"Pi:leaving room\n")
        else:
            print("irc:no valid command received")
            sendmultiblock(rc,"Pi:No valid command received")
    except Exception as e:
            print("irc:Caught exception"+str(e))
            sendmultiblock(rc,"Pi:"+str(e))
    
def dskioini(iniflag = ''):
    print("dskioini")
    if len(iniflag) == 0:
        iniflag = piexchangebyte()

    global msxdos1boot,sectorInfo,numdrivesM,drive0Data,drive1Data
    
    if iniflag == '1':
        #print("DOS: Enabling MSX-DOS1")

        msxdos1boot = True

        # Initialize disk system parameters
        sectorInfo = [0,0,0,0]
        numdrives = 0

        # Load the disk images into a memory mapped variable
        rc , drive0Data = msxdos_inihrd(psetvar[1][1])
        rc , drive1Data = msxdos_inihrd(psetvar[2][1])
    else:
        #print("parms: disabling msxdos1boot")
        msxdos1boot = False

def dskiords():
    print("dskiords")
    initdataindex = sectorInfo[3]*SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    #print("dos_rds:deviceNumber=",sectorInfo[0])
    #print("dos_rds:numsectors=",sectorInfo[1])
    #print("dos_rds:mediaDescriptor=",sectorInfo[2])
    #print("dos_rds:initialSector=",sectorInfo[3])
    #print("dos_rds:blocksize=",SECTORSIZE)
    
    while sectorcnt < numsectors:
        if sectorInfo[0] == 0:
            buf = drive0Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)]
        else:
            buf = drive1Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)]
        rc = senddata(buf,SECTORSIZE)
        sectorcnt += 1
        if  rc == RC_CRCERROR:
            print("senddata: checksum error")
            break
 
def dskiowrs():
    print("dskiowrs")
    initdataindex = sectorInfo[3]*SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    #print("dos_wrs:deviceNumber=",sectorInfo[0])
    #print("dos_wrs:numsectors=",sectorInfo[1])
    #print("dos_wrs:mediaDescriptor=",sectorInfo[2])
    #print("dos_wrs:initialSector=",sectorInfo[3])
    #print("dos_wrs:blocksize=",SECTORSIZE)
    
    while sectorcnt < numsectors:
        rc,buf = recvdata(SECTORSIZE)
        if  rc == RC_SUCCESS:
            if sectorInfo[0] == 0:
                drive0Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = buf
            else:
                drive1Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = buf
            sectorcnt += 1
        else:
            break
                  
def dskiosct():
    print("dskiosct")
    #if msxdos1boot != True:
    #   piexchangebyte(RC_FAILED)
    #  return

    global msxdos1boot,sectorInfo,numdrivesM,drive0Data,drive1Data

    route = 2
    
    if route == 1:             
        rc,buf = recvdata(5)
        sectorInfo[0] = buf[0]
        sectorInfo[1] = buf[1]
        sectorInfo[2] = buf[2]
        byte_lsb = buf[3]
        byte_msb = buf[4]
        sectorInfo[3] = byte_lsb + 256 * byte_msb

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
          
    #print("dos_sct:deviceNumber=",sectorInfo[0])
    #print("dos_sct:numsectors=",sectorInfo[1])
    #print("dos_sct:mediaDescriptor=",sectorInfo[2])
    #print("dos_sct:initialSector=",sectorInfo[3])
       
def recvdata( bytecounter = BLKSIZE):

    print("recvdata")
    
    retries = GLOBALRETRIES
    while retries > 0:
        retries -= 1
        
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
            rc = RC_CRCERROR
            print("recvdata: checksum error")

    #print (hex(rc))
    return rc,data

def senddata(data, blocksize = BLKSIZE):
    
    print("senddata")
   
    retries = GLOBALRETRIES
    while retries > 0:
        retries -= 1
        
        byteidx = 0
        chksum = 0
    
        while(byteidx < blocksize):
            #print(byteidx)
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
            rc = RC_CRCERROR
            print("senddata: checksum error")

    #print (hex(rc))
    return rc

def sendmultiblock(buf, blocksize = BLKSIZE):
    print("sendmultiblock")
    idx = 0
    cnt = 0
    data = bytearray(blocksize)
    for b in buf:
        if (isinstance(b, str)):
            data[cnt] = ord(b)
        else:
            data[cnt] = b
        cnt += 1   
        if cnt == blocksize and blocksize < len(buf):
            #print(len(data),data)
            #print("sendmultiblock:",idx,cnt)
            rc = senddata(data, blocksize)
            if rc != RC_SUCCESS:
                return RC_FAILED
                
            data = bytearray(blocksize)
            idx += blocksize
            cnt = 0
    #print(len(data),data)
    #print("sendmultiblock:",idx,cnt)
    if cnt > 0:
        rc = senddata(data,blocksize)          
    return rc
   
def send_rc_msg(rc,msg):
    #print("send_rc_msg:",rc,msg)
    
    buf = bytearray()
    buf.extend(rc.to_bytes(1,'little'))
    buf.extend(msg.encode())
    
    rc = sendmultiblock(buf, MSGSIZE)
    return rc

def template():
    print("template now receiving parameters...")
    
    # Parameters have always a fixed size: BLKSIZE
    rc,data = recvdata(BLKSIZE)    
    print("Raw data received:",data)
    
    print("Extracting only ascii bytes and setting reponse...")
    buf = 'MSXPi received: ' + data.decode().split("\x00")[0]
    
    print("Sending response: ",buf) 
    rc = sendmultiblock(buf, BLKSIZE)

def recvcmd():
    print("recvcmd")
      
    retries = GLOBALRETRIES
    while retries > 0:
        retries -= 1
        
        # Syncronize with MSX
        while piexchangebyte() != READY: # WAS 0x9F:
            pass
        
        bytecounter = CMDSIZE
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
            rc = RC_CRCERROR
            print("recvdata: checksum error")

    return rc,data.decode().split("\x00")[0]
        
""" ============================================================================
    msxpi-server.py
    main program starts here
    ============================================================================
"""

psetvar = [['PATH','/home/pi/msxpi'], \
           ['DRIVE0','disks/msxpiboot.dsk'], \
           ['DRIVE1','disks/msxpitools.dsk'], \
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

# msxdos
msxdos1boot = True

errcount = 0

init_spi_bitbang()
GPIO.output(rdyPin, GPIO.LOW)
print("GPIO Initialized\n")
print("Starting MSXPi Server Version ",version,"Build",BuildId)

dskioini("1")

try:
    while True:
        try:
            #print("st_recvcmd: waiting command")
            rc,fullcmd = recvcmd()
            print(fullcmd)
            
            if (rc == RC_SUCCESS and len(fullcmd) > 0):
                err = 0
                cmd = fullcmd.split()[0].lower()
                parms = fullcmd[len(cmd)+1:]
                #print("cmd: calling command ",cmd)
             
                # Executes the command (first word in the string)
                # And passes the whole string (including command name) to the function
                # globals()['use_variable_as_function_name']() 
                globals()[cmd.strip()]()
        except Exception as e:
            errcount += 1
            print("Error in cmd received:"+str(e))

except KeyboardInterrupt:
    GPIO.cleanup() # cleanup all GPIO
    print("Terminating msxpi-server")
