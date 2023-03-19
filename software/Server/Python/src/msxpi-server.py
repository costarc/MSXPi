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
from random import randint

version = "1.1"
build = "20230305.003"
BLKSIZE = 256
SECTORSIZE = 512
CMDSIZE = 9

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

def recvdatablock():
    buffer = bytearray()
    bytecounter = 0
    crc = 0
    rc = RC_SUCCESS
    
    msxbyte = piexchangebyte(SENDNEXT)
    if (msxbyte != SENDNEXT):
        print("recvdatablock:Out of sync with MSX")
        rc = RC_OUTOFSYNC
    else:
        dsL = piexchangebyte(SENDNEXT)
        dsM = piexchangebyte(SENDNEXT)
        datasize = dsL + 256 * dsM
        
        #print "recvdatablock:Received blocksize =",datasize
        while(datasize>bytecounter):
            msxbyte = piexchangebyte(SENDNEXT)
            buffer.append(msxbyte)
            crc ^= msxbyte
            bytecounter += 1

        msxcrc = piexchangebyte(crc)
        if (msxcrc != crc):
            rc = RC_CRCERROR

    #print "recvdatablock:exiting with rc = ",hex(rc)
    return [rc,buffer]

def senddatablock(buf,blocksize,blocknumber,attempts=GLOBALRETRIES):
    
    print("senddatablock: Block size,blocknumber,attempts:",blocksize,blocknumber,attempts)
    global GLOBALRETRIES

    rc = RC_FAILED
    
    bufsize = len(buf)
    bufpos = blocksize*blocknumber

    if (blocksize <= bufsize - bufpos):
        thisblocksize = blocksize
    else:
        thisblocksize = bufsize - bufpos
        if thisblocksize < 0:
            thisblocksize = 0

    msxbyte = piexchangebyte(SENDNEXT)

    if (msxbyte != SENDNEXT):
        print("senddatablock:Out of sync with MSX, waiting SENDNEXT, received",hex(msxbyte),hex(msxbyte))
        return RC_OUTOFSYNC
    else:
        piexchangebyte(thisblocksize % 256)
        piexchangebyte(thisblocksize // 256)
        if thisblocksize == 0:
            return ENDTRANSFER

    piexchangebyte(attempts)

    while (attempts > 0 and rc != RC_SUCCESS):
        crc = 0xffff
        bytecounter = 0
        while(bytecounter < thisblocksize):
            pibyte0 = buf[bufpos+bytecounter]
            #print("senddatablock: ord() checkpoint indata is ",type(pibyte0))
            if type(pibyte0) is int:
                pibyte = pibyte0
            else:
                pibyte = ord(pibyte0)

            #print("senddatablock: ord() checkpoint outdata is ",type(pibyte0))
            #print("senddatablock: ord() checkpoint 1:end")
            piexchangebyte(pibyte)
            
            #print("senddatablock: calling crc16")
            
            crc = crc16(crc,pibyte)
            bytecounter += 1
            
        msxcrcL = piexchangebyte(crc % 256)
        if msxcrcL != crc % 256:
            attempts -= 1
            rc = RC_CRCERROR
            print("RC_CRCERROR. Remaining attempts:",attempts)
        else:
            msxcrcH = piexchangebyte(crc // 256)
            if msxcrcH != crc // 256:
                attempts -= 1
                rc = RC_CRCERROR
                print("RC_CRCERROR. Remaining attempts:",attempts)

            else:
                rc = RC_SUCCESS
    
    return rc 

def sendmultiblock(buf, size = BLKSIZE):
    idx = 0
    cnt = 0
    data = bytearray(size)
    for b in buf:
        if (isinstance(b, str)):
            data[cnt] = ord(b)
        else:
            data[cnt] = b
        cnt += 1   
        if cnt == size and len(buf) > size:
            print(len(data),data)
            rc = senddata(data)
            data = bytearray(size)
            idx += size
            cnt = 0
   
    rc = senddata(data)          
    return rc

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
    elif (path.startswith('http') or \
          path.startswith('ftp') or \
          path.startswith('nfs') or \
          path.startswith('smb')):
        urltype = 2 # this is an absolute network path
        newpath = path
    elif basepath.startswith('/'):
        urltype = 1 # this is an relative local path
        newpath = basepath + "/" + path
    elif (basepath.startswith('http') or \
          basepath.startswith('ftp') or \
          basepath.startswith('nfs') or \
          basepath.startswith('smb')):
        urltype = 3 # this is an relative network path
        newpath = basepath + "/" + path

    return [urltype, newpath]

def msxdos_inihrd(filename, access=mmap.ACCESS_WRITE):
    #print "msxdos_inihrd:Starting"
    size = os.path.getsize(filename)
    if (size>0):
        fd = os.open(filename, os.O_RDWR)
        rc = mmap.mmap(fd, size, access=access)
    else:
        rc = RC_FAILED

    return rc

def dos83format(fname):
    name = '        '
    ext = '   '

    finfo = fname.split('.')

    name = str(finfo[0]).ljust(8)
    if len(finfo) == 2:
        ext = str(finfo[1]).ljust(3)
    
    return name+ext

def ini_fcb(fname):

    print("ini_fcb: starting")
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

    print("Drive, Filename:",msxdrive,msxfcbfname)

    # send FCB structure to MSX
    piexchangebyte(msxdrive)
    for i in range(0,11):
        piexchangebyte(ord(msxfcbfname[i]))
    
    print("ini_fcb: Exiting")

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
        print("prun else")
        cmd = cmd.replace('::','|')
        try:
            #print("prun: inside try: cmd = ",cmd)
            p = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
            buf = p.stdout.read().decode()
            #print("prun: Popen stdout = ",buf)
            if len(buf) == 0:
                buf = "Pi:No output"

            sendmultiblock(buf)

        except Exception as e:
            print("prun: exception")
            rc = RC_FAILED
            sendmultiblock("Pi:"+str(e)+'\n')

    print("prun:exiting rc:",hex(rc))
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
            print("pdir: if1")
            urlcheck = getpath(basepath, path)
            if (urlcheck[0] == 0 or urlcheck[0] == 1):
                print("pdir: if2")
                if (path.strip() == '*'):
                    prun('ls -l ' + urlcheck[1])
                elif ('*' in path):
                    print("pdir: elif1")
                    numChilds = path.count('/')
                    fileDesc = path.rsplit('/', 1)[numChilds].replace('*','')
                    if (fileDesc == '' or len(fileDesc) == 0):
                        fileDesc = '.'
                    prun('ls -l ' + urlcheck[1].rsplit('/', 1)[0] + '/|/bin/grep '+ fileDesc)
                else:
                    print("pdir: else inside",urlcheck[1])
                    prun('ls -l ' + urlcheck[1])
            else:
                print("pdir: else out")
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
        print("pdir exception 2:"+str(e))
        sendmultiblock('Pi:'+str(e))

    print("pdir:exiting rc:",hex(rc))
    return rc

def pcd():    
    rc = RC_SUCCESS
    global psetvar
    basepath = psetvar[0][1]
    newpath = basepath
    
    print("pcd: system path:",basepath)
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

                if (newpath[:4] == "http" or \
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
    
    rc,data = recvdata()
    path = data.decode().split("\x00")[0]
    
    print("pcopy: Starting with params ",path)
    
    if (path.startswith('http') or \
        path.startswith('ftp') or \
        path.startswith('nfs') or \
        path.startswith('smb') or \
        path.startswith('/')):
        fileinfo = path
    elif path == '':
        fileinfo = basepath
    else: 
        fileinfo = basepath+'/'+path

    fileinfo = fileinfo.split()

    print("pcopy: parsed parameters: ",fileinfo)
    
    if len(fileinfo) == 1:
        fname_rpi = str(fileinfo[0])
        fname_msx_0 = fname_rpi.split('/')
        fname_msx = str(fname_msx_0[len(fname_msx_0)-1])
    elif len(fileinfo) == 2:
        fname_rpi = str(fileinfo[0])
        fname_msx = str(fileinfo[1])
    else:
        sendmultiblock("Pi:Command line parametrs invalid.")
        return RC_FAILED

    urlcheck = getpath(basepath, path)
    # basepath 0 local filesystem
    if (urlcheck[0] == 0 or urlcheck[0] == 1):
        print("pcopy: path is local")
        
        try:
            with open(fname_rpi, mode='rb') as f:
                buf = f.read()

            filesize = len(buf)
 
        except Exception as e:
            rc = 1
            buf = formatrsp(rc,0,0,str(e))
            rc = sendmultiblock(buf)
            return rc

    else:
        print("pcopy: path is remote")
        try:
            urlhandler = urlopen(fname_rpi)
            print("pcopy:urlopen rc:",urlhandler.getcode())
            buf = urlhandler.read()
            filesize = len(buf)
            
        except Exception as e:
            rc = 1
            buf = formatrsp(rc,0,0,str(e))
            rc = sendmultiblock(buf)
            
    if rc == RC_SUCCESS:
        print("pcopy: File open success, size is ",filesize)
        if filesize == 0:
            rc = 1
            buf = formatrsp(rc,0,0,"No valid data found")
            rc = sendmultiblock(buf)
        else:
            if inifcb:
                msxbyte = piexchangebyte(RC_SUCCESS)
                ini_fcb(fname_msx)
            else:
                if filesize > 32768:
                    return RC_INVALIDDATASIZE

                msxbyte = piexchangebyte(RC_SUCCESS)
            blocknumber = 0   
            print("pcopy: Calling senddata")
            rc = sendmultiblock(buf)
    print("pcopy: exit with rc",rc)
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


def pplay(cmd):
    rc = RC_SUCCESS
    
    cmd = "bash " + RAMDISK + "/pplay.sh " + " PPLAY "+psetvar[0][1]+ " "+cmd+" >" + RAMDISK + "/msxpi.tmp"
    cmd = str(cmd)
    
    print("pplay:starting command:len:",cmd,len(cmd))

    try:
        p = subprocess.call(cmd, shell=True)
        buf = msxdos_inihrd(RAMDISK + "/msxpi.tmp")
        if (buf == RC_FAILED):
            sendmultiblock("Pi:Ok\n")
        else:
            sendmultiblock(buf)
    except subprocess.CalledProcessError as e:
        rc = RC_FAILED
        sendmultiblock("Pi:"+str(e))
    
    #print "pplay:exiting rc:",hex(rc)
    return rc

def pset():
    global psetvar
    
    rc = RC_SUCCESS
    buf = "Pi:\nSyntax: pset set <var> <value>"
    cmd = cmd.strip()

    if (len(cmd)==0 or cmd[:1] == "d" or cmd[:1] == "D"):
        s = str(psetvar)
        buf = s.replace(", ",",").replace("[[","").replace("]]","").replace("],","\n").replace("[","").replace(",","=").replace("'","")
    
    elif (cmd[:1] == "s" or cmd[:1] == "S"):
        cmd=cmd.split(" ")
        found = False
        if (len(cmd) == 3):
            for index in range(0,len(psetvar)):
                if (psetvar[index][0] == str(cmd[1])):
                    psetvar[index][1] = str(cmd[2])
                    found = True
                    buf = "Pi:Ok\n"
                    rc_text = psetvar[index][0];
                    break

            if (not found):
                for index in range(7,len(psetvar)):
                    if (psetvar[index][0] == "free"):
                        psetvar[index][0] = str(cmd[1])
                        psetvar[index][1] = str(cmd[2])
                        found = True
                        buf = "Pi:Ok\n"
                        rc_text = psetvar[index][0];
                        break

            if (not found):
                rc = RC_FAILED
                rc_text = '';
                buf = "Pi:Error setting parameter"
        else:
            rc = RC_FAILED

    sendmultiblock(buf)

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
    sendmultiblock(ver)

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
        print("DOS: Enabling MSX-DOS1")

        msxdos1boot = True

        # Initialize disk system parameters
        sectorInfo = [0,0,0,0]
        numdrives = 0

        # Load the disk images into a memory mapped variable
        drive0Data = msxdos_inihrd(psetvar[1][1])
        drive1Data = msxdos_inihrd(psetvar[2][1])
    else:
        #print("parms: disabling msxdos1boot")
        msxdos1boot = False

def dskiords():
    initdataindex = sectorInfo[3]*SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    print("dos_rds:deviceNumber=",sectorInfo[0])
    print("dos_rds:numsectors=",sectorInfo[1])
    print("dos_rds:mediaDescriptor=",sectorInfo[2])
    print("dos_rds:initialSector=",sectorInfo[3])
    print("dos_rds:blocksize=",SECTORSIZE)
    
    while sectorcnt < numsectors:
        if sectorInfo[0] == 0 or sectorInfo[0] == 1:
            buf = drive0Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)]
        else:
            buf = drive1Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)]
        rc = senddata(buf,SECTORSIZE)
        sectorcnt += 1
        if  rc == RC_CRCERROR:
            print("senddata: checksum error")
            break
 
def dskiowrs():
    initdataindex = sectorInfo[3]*SECTORSIZE
    numsectors = sectorInfo[1]
    sectorcnt = 0
    
    print("dos_wrs:deviceNumber=",sectorInfo[0])
    print("dos_wrs:numsectors=",sectorInfo[1])
    print("dos_wrs:mediaDescriptor=",sectorInfo[2])
    print("dos_wrs:initialSector=",sectorInfo[3])
    print("dos_wrs:blocksize=",SECTORSIZE)
    
    while sectorcnt < numsectors:
        rc,buf = recvdata(SECTORSIZE)
        if  rc == RC_SUCCESS:
            if sectorInfo[0] == 0 or sectorInfo[0] == 1:
                print("A:",data)
                #drive0Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = str(data)
            else:
                print("B:",data)
                #drive1Data[initdataindex+(sectorcnt*SECTORSIZE):initdataindex+SECTORSIZE+(sectorcnt*SECTORSIZE)] = str(data)
            sectorcnt += 1
        else:
            break
                  
def dskiosct():
    print("dskiosct")
    #if msxdos1boot != True:
    #   piexchangebyte(RC_FAILED)
    #  return

    global msxdos1boot,sectorInfo,numdrivesM,drive0Data,drive1Data
    
    rc,buf = recvdata(CMDSIZE)
    sectorInfo[0] = buf[0]
    sectorInfo[1] = buf[1]
    sectorInfo[2] = buf[2]
    byte_lsb = buf[3]
    byte_msb = buf[4]
    sectorInfo[3] = byte_lsb + 256 * byte_msb

    print("dos_sct:deviceNumber=",sectorInfo[0])
    print("dos_sct:numsectors=",sectorInfo[1])
    print("dos_sct:mediaDescriptor=",sectorInfo[2])
    print("dos_sct:initialSector=",sectorInfo[3])
        
def recvdata( bytecounter = BLKSIZE):

    print("recvdata")
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
        print("recvdata: checksum is a match")
    else:
        rc = RC_CRCERROR
        print("recvdata: checksum error")


    #print "recvdata:exiting with rc = ",hex(rc)
    return rc,data

def senddata(data, blocksize = BLKSIZE):
    
    print("senddata")
   
    byteidx = 0
    chksum = 0
    while(byteidx < blocksize):
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
        print("senddata: checksum is a match")
    else:
        rc = RC_CRCERROR
        print("senddata: checksum error")

    return rc

def template():
    print("template now receiving parameters...")
    
    rc,data = recvdata()    
    print("Raw data received:",data)
    
    print("Extracting only ascii bytes and setting reponse...")
    rsp = 'MSXPi received: ' + data.decode().split("\x00")[0]
    
    print()
    print("Creating a bytearray of size BLKSIZE and inserting the response. The full response is padded with zeros")
    # pad data to send to senddata function
    data = bytearray(BLKSIZE)
    idx = 0
    for c in rsp:
        data[idx] = ord(c)
        idx += 1
    
    print("Sending response: ",data) 
    rc = senddata(data)

def recvcmd():
    print("recvcmd")
    rc,data = recvdata(CMDSIZE)
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
print("Starting MSXPi Server Version ",version,"Build",build)

dskioini("1")

#try:
if 1==1:
    while True:
        #try:
        if 1==1:
            print("st_recvcmd: waiting command")
            rc,fullcmd = recvcmd()
            
            print("Received:",fullcmd,len(fullcmd))

            if (rc == RC_SUCCESS and len(fullcmd) > 0):
                err = 0
                cmd = fullcmd.split()[0].lower()
                parms = fullcmd[len(cmd)+1:]
                print("cmd: calling command ",cmd)
             
                # Executes the command (first word in the string)
                # And passes the whole string (including command name) to the function
                # globals()['use_variable_as_function_name']() 
                globals()[cmd.strip()]()
        #except Exception as e:
        #errcount += 1
        #print("Error in cmd received:"+str(e))

#except KeyboardInterrupt:
#    GPIO.cleanup() # cleanup all GPIO
#    print("Terminating msxpi-server")
