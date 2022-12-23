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

version = "1.0.1"
build = "20221223.000"
BLKSIZE = 1024

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
        if (byte_out & bit):
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
        piexchangebyte(thisblocksize / 256)
        if thisblocksize == 0:
            return ENDTRANSFER

    piexchangebyte(attempts)

    while (attempts > 0 and rc != RC_SUCCESS):
        crc = 0xffff
        bytecounter = 0
        while(bytecounter < thisblocksize):
            pibyte = ord(buf[bufpos+bytecounter])
            piexchangebyte(pibyte)
            crc = crc16(crc,pibyte)
            bytecounter += 1

        msxcrcL = piexchangebyte(crc % 256)
        if msxcrcL != crc % 256:
            attempts -= 1
            rc = RC_CRCERROR
            print("RC_CRCERROR. Remaining attempts:",attempts)
        else:
            msxcrcH = piexchangebyte(crc / 256)
            if msxcrcH != crc / 256:
                attempts -= 1
                rc = RC_CRCERROR
                print("RC_CRCERROR. Remaining attempts:",attempts)

            else:
                rc = RC_SUCCESS
    
    return rc 

def sendstdmsg(rc, message):
    piexchangebyte(rc)
    senddatablock(message,len(message),0,1)

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

    #print("Drive, Filename:",msxdrive,msxfcbfname)

    # send FCB structure to MSX
    piexchangebyte(msxdrive)
    for i in range(0,11):
        piexchangebyte(ord(msxfcbfname[i]))

def prun(cmd):
    piexchangebyte(RC_WAIT)
    rc = RC_SUCCESS

    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        print("prun:syntax error")
        sendstdmsg(RC_FAILED,"Syntax: prun <command> <::> command\nTo pipe a command to other, use :: instead of |")
        rc = RC_FAILED
    else:
        cmd = cmd.replace('::','|')
        try:

            p = Popen(cmd.decode(), shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
            buf = p.stdout.read()
            if len(buf) == 0:
                buf = "Pi:No output"

            sendstdmsg(rc,buf)

        except Exception as e:
            rc = RC_FAILED
            sendstdmsg(rc,"Pi:"+str(e)+'\n')

    #print "prun:exiting rc:",hex(rc)
    return rc

def pdir(path):
    msxbyte = piexchangebyte(RC_WAIT)
    global psetvar
    basepath = psetvar[0][1]
    rc = RC_SUCCESS
    #print "pdir:starting"

    try:
        if (msxbyte == SENDNEXT):
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
                    htmldata = urllib2.urlopen(urlcheck[1].decode()).read()
                    parser = MyHTMLParser()
                    parser.feed(htmldata)
                    buf = " ".join(parser.HTMLDATA)
                    piexchangebyte(RC_SUCCESS)
                    rc = senddatablock(buf,len(buf),0,1)

                except urllib2.HTTPError as e:
                    rc = RC_FAILED
                    print("pdir:http error "+ str(e))
                    sendstdmsg(rc,str(e))
        else:
            rc = RC_FAILNOSTD
            print("pdir:out of sync in RC_WAIT")
    except Exception as e:
        print("pdir:"+str(e))
        sendstdmsg(RC_FAILED,'Pi:'+str(e))

    #print "pdir:exiting rc:",hex(rc)
    return rc

def pcd(path):    
    msxbyte = piexchangebyte(RC_WAIT)
    rc = RC_SUCCESS
    global psetvar
    basepath = psetvar[0][1]
    newpath = basepath
    
    #print "pcd:starting basepath:path=",basepath + ":" + path

    try:
        if (msxbyte == SENDNEXT):
            if (path == '' or path.strip() == "."):
                sendstdmsg(rc,basepath+'\n')
            elif (path.strip() == ".."):
                newpath = basepath.rsplit('/', 1)[0]
                if (newpath == ''):
                    newpath = '/'
                psetvar[0][1] = newpath
                sendstdmsg(rc,str(newpath+'\n'))
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
                    sendstdmsg(rc,str(newpath+'\n'))
                else:
                    newpath = str(newpath)
                    if (os.path.isdir(newpath)):
                        psetvar[0][1] = newpath
                        sendstdmsg(rc,newpath+'\n')
                    elif (os.path.isfile(str(newpath))):
                        sendstdmsg(RC_FAILED,"Pi:Error - not a folder")
                    else:
                        sendstdmsg(RC_FAILED,"Pi:Error - path not found")
        else:
            rc = RC_FAILNOSTD
            print("pcd:out of sync in RC_WAIT")
    except Exception as e:
        print("pcd:"+str(e))
        sendstdmsg(RC_FAILED,'Pi:'+str(e))

    return [rc, newpath]

def pcopy(path='',inifcb=True):
    piexchangebyte(RC_WAIT)

    buf = ''
    rc = RC_SUCCESS

    global psetvar,GLOBALRETRIES
    basepath = psetvar[0][1]
    
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

    if len(fileinfo) == 1:
        fname_rpi = str(fileinfo[0])
        fname_msx_0 = fname_rpi.split('/')
        fname_msx = str(fname_msx_0[len(fname_msx_0)-1])
    elif len(fileinfo) == 2:
        fname_rpi = str(fileinfo[0])
        fname_msx = str(fileinfo[1])
    else:
        sendstdmsg(RC_FAILED,"Pi:Command line parametrs invalid.")
        return RC_FAILED

    urlcheck = getpath(basepath, path)
    # basepath 0 local filesystem
    if (urlcheck[0] == 0 or urlcheck[0] == 1):
        try:
            with open(fname_rpi, mode='rb') as f:
                buf = f.read()

            filesize = len(buf)
 
        except Exception as e:
            sendstdmsg(RC_FAILED,"Pi:"+str(e)+'\n') 
            return RC_FAILED

    else:
        try:
            urlhandler = urllib2.urlopen(fname_rpi)
            #print("pcopy:urlopen rc:",urlhandler.getcode())
            buf = urlhandler.read()
            filesize = len(buf)
            
        except Exception as e:
            rc = RC_FAILED
            sendstdmsg(RC_FAILED,"Pi:"+str(e))
    
    if rc == RC_SUCCESS:
        if filesize == 0:
            sendstdmsg(RC_FILENOTFOUND,"Pi:No valid data found")
        else:
            if inifcb:
                msxbyte = piexchangebyte(RC_SUCCESS)
                ini_fcb(fname_msx)
            else:
                if filesize > 32768:
                    return RC_INVALIDDATASIZE

                msxbyte = piexchangebyte(RC_SUCCESS)
            blocknumber = 0   
            while (rc == RC_SUCCESS):
                rc = senddatablock(buf,BLKSIZE,blocknumber)
                if rc == RC_SUCCESS:
                    blocknumber += 1

    return rc

def ploadr(path=''):
    rc = pcopy(path,False)
    if rc == RC_INVALIDDATASIZE:
        sendstdmsg(RC_FAILED,"Pi:Error - Not valid 8/16/32KB ROM")

def pdate(parms = ''):
    msxbyte = piexchangebyte(RC_WAIT)

    rc = RC_FAILED
    
    if (msxbyte == SENDNEXT):
        now = datetime.datetime.now()

        msxbyte = piexchangebyte(RC_SUCCESS)
        if (msxbyte == SENDNEXT):
            piexchangebyte(now.year & 0xff)
            piexchangebyte(now.year >>8)
            piexchangebyte(now.month)
            piexchangebyte(now.day)
            piexchangebyte(now.hour)
            piexchangebyte(now.minute)
            piexchangebyte(now.second)
            piexchangebyte(0)
            buf = "Pi:Ok"
            senddatablock(buf,len(buf),0)
            rc = RC_SUCCESS
        else:
            print("pdate:out of sync in SENDNEXT")
    else:
        print("pdate:out of sync in RC_WAIT")

    return rc

def pplay(cmd):
    rc = RC_SUCCESS
    
    cmd = "bash " + RAMDISK + "/pplay.sh " + " PPLAY "+psetvar[0][1]+ " "+cmd+" >" + RAMDISK + "/msxpi.tmp"
    cmd = str(cmd)
    
    #print "pplay:starting command:len:",cmd,len(cmd)

    piexchangebyte(RC_WAIT)
    try:
        p = subprocess.call(cmd, shell=True)
        buf = msxdos_inihrd(RAMDISK + "/msxpi.tmp")
        if (buf == RC_FAILED):
            sendstdmsg(RC_SUCCESS,"Pi:Ok\n")
        else:
            sendstdmsg(rc,buf)
    except subprocess.CalledProcessError as e:
        rc = RC_FAILED
        sendstdmsg(rc,"Pi:"+str(e))
    
    #print "pplay:exiting rc:",hex(rc)
    return rc

def pset(cmd=''):
    piexchangebyte(RC_WAIT)

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

    sendstdmsg(rc,buf)

    return rc

def pwifi(parms=''):
    piexchangebyte(RC_WAIT)

    global psetvar
    wifissid = psetvar[4][1]
    wifipass = psetvar[5][1]
    rc = RC_SUCCESS
    cmd=parms.decode().strip()

    if (cmd[:2] == "/h"):
        sendstdmsg(RC_FAILED,"Pi:Usage:\npwifi display | set")
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
        rc = RC_SUCCESS
    else:
        prun("ip a | grep '^1\\|^2\\|^3\\|^4\\|inet'|grep -v inet6")
    
    return rc

def pver(parms=''):
    piexchangebyte(RC_WAIT)
    global version,build
    ver = "MSXPi Server Version "+version+" Build "+build
    sendstdmsg(RC_SUCCESS,ver)

def template(parms=''):
    piexchangebyte(RC_WAIT)

    """ Do something that takes time, for example, opening and parsing a file
    ; or loading something from the network or internet.
    """
    time.sleep(2)

    """
    Next step is to return a rc (Return Code) to MSX
    Since this template only returns a string to MSX,
    we using the function sendstdmsg(<return code><string>) because
    it will:
      1) send the RC to msx (first parameter)
      2) send the text (second parameter)
    """

    if parms == '':
        sendstdmsg(RC_FAILED,"Pi:No parameters passed")
    else:
        sendstdmsg(RC_SUCCESS,"Pi:Received paramter(s):"+parms)

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
            sendstdmsg(rc,ircmsg)
        elif cmd[:3] == "msg":
            print("msg:sending msg ",cmd[:4])
            ircsock.send(bytes("PRIVMSG "+ channel +" :" + cmd[4:] +"\n"))
            sendstdmsg(RC_SUCCNOSTD,"Pi:Ok\n")
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

            sendstdmsg(RC_SUCCESS,ircmsg)

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
            sendstdmsg(rc,ircmsg)

        elif cmd[:5] == 'names':
            ircsock.send(bytes("NAMES " + channel + "\n"))
            ircmsg = ''
            ircmsg = ircmsg + ircsock.recv(2048).decode("UTF-8")
            ircmsg = ircmsg.strip('\n\r')
            ircmsg = "Users on channel " + ircmsg.split('=',1)[1]
            sendstdmsg(RC_SUCCESS,ircmsg)
        elif cmd[:4] == 'quit':
            ircsock.send(bytes("/quit\n"))
            ircsock.close()
            sendstdmsg(RC_SUCCESS,"Pi:leaving room\n")
        elif cmd[:4] == 'part':
            ircsock.send(bytes("/part\n"))
            ircsock.close()
            sendstdmsg(RC_SUCCESS,"Pi:leaving room\n")
        else:
            print("irc:no valid command received")
            sendstdmsg(rc,"Pi:No valid command received")
    except Exception as e:
            print("irc:Caught exception"+str(e))
            sendstdmsg(rc,"Pi:"+str(e))

def dos(parms=''):
    piexchangebyte(RC_WAIT)

    global msxdos1boot,sectorInfo,numdrivesM,drive0Data,drive1Data
    rc = RC_SUCCESS

    try:
        if parms[:3] == 'INI': 

            piexchangebyte(RC_SUCCESS)

            iniflag = parms[4:5]

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

            piexchangebyte(RC_SUCCESS)


        elif parms[:3] == 'RDS': 
        
            initdataindex = sectorInfo[3]*512
            blocksize = sectorInfo[1]*512

            """
            print("dos_rds:deviceNumber=",sectorInfo[0])
            print("dos_rds:numsectors=",sectorInfo[1])
            print("dos_rds:mediaDescriptor=",sectorInfo[2])
            print("dos_rds:initialSector=",sectorInfo[3])
            print("dos_rds:blocksize=",blocksize)
            """

            if sectorInfo[0] == 0 or sectorInfo[0] == 1:
                buf = drive0Data[initdataindex:initdataindex+blocksize]
            else:
                buf = drive1Data[initdataindex:initdataindex+blocksize]

            piexchangebyte(RC_SUCCESS)

            rc = senddatablock(buf,blocksize,0)
            if rc != RC_SUCCESS:
                rc = RC_FAILED
            
            piexchangebyte(rc)


        elif parms[:3] == 'WRS':  
            initdataindex = sectorInfo[3]*512
            blocksize = sectorInfo[1]*512

            """
            print("dos_wrs:deviceNumber=",sectorInfo[0])
            print("dos_wrs:numsectors=",sectorInfo[1])
            print("dos_wrs:mediaDescriptor=",sectorInfo[2])
            print("dos_wrs:initialSector=",sectorInfo[3])
            print("dos_wrs:blocksize=",blocksize)
            """

            piexchangebyte(RC_SUCCESS)

            datainfo = recvdatablock()
            if datainfo[0] == RC_SUCCESS:
                if sectorInfo[0] == 0 or sectorInfo[0] == 1:
                    drive0Data[initdataindex:initdataindex+blocksize] = str(datainfo[1])
                else:
                    drive1Data[initdataindex:initdataindex+blocksize] = str(datainfo[1])
            else:
                rc = RC_FAILED

            piexchangebyte(rc)
                  
        elif parms[:3] == 'SCT':
            if msxdos1boot != True:
                piexchangebyte(RC_FAILED)
                return

            piexchangebyte(RC_SUCCESS)

            sectorInfo[0] = piexchangebyte(SENDNEXT)
            sectorInfo[1] = piexchangebyte(SENDNEXT)
            sectorInfo[2] = piexchangebyte(SENDNEXT)
            byte_lsb = piexchangebyte(SENDNEXT)
            byte_msb = piexchangebyte(SENDNEXT)
            sectorInfo[3] = byte_lsb + 256 * byte_msb

            blocksize = sectorInfo[1] * 512
            piexchangebyte(blocksize % 256)
            piexchangebyte(blocksize / 256)

            """
            print("dos_sct:deviceNumber=",sectorInfo[0])
            print("dos_sct:numsectors=",sectorInfo[1])
            print("dos_sct:mediaDescriptor=",sectorInfo[2])
            print("dos_sct:initialSector=",sectorInfo[3])
            print("dos_sct:blocksize=",blocksize)
            """

            piexchangebyte(RC_SUCCESS)

    except Exception as e:
        print("DOS:"+str(e))
        piexchangebyte(RC_FAILED)

def ping(parms=''):
    piexchangebyte(RC_SUCCNOSTD)

def resync():
    print("sync")
    msxbyte = piexchangebytewithtimeout(READY,2)
    while (msxbyte != ABORT):
        msxbyte = piexchangebytewithtimeout(READY,2)
    return

def recvcmd(cmdlength=128):
    buffer = bytearray()
    bytecounter = 0
    crc = 0
    rc = RC_SUCCESS
    
    msxbyte = piexchangebyte(SENDNEXT)
    if (msxbyte != SENDNEXT):
        print("recvcmd:Out of sync with MSX:",hex(msxbyte))
        rc = RC_OUTOFSYNC
    else:
        dsL = piexchangebyte(SENDNEXT)
        dsM = piexchangebyte(SENDNEXT)
        datasize = dsL + 256 * dsM
        
        if datasize > cmdlength:
            print("recvcmd:Error - Command too long")
            return [RC_INVALIDCOMMAND,datasize]

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

""" ============================================================================
    msxpi-server.py
    main program starts here
    ============================================================================
"""

psetvar = [['PATH','/home/msxpi'], \
           ['DRIVE0','disks/msxpiboot.dsk'], \
           ['DRIVE1','disks/50dicas.dsk'], \
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

# dos("INI 1")

try:
    while True:
        try:
            print("st_recvcmd: waiting command")
            rc = recvcmd()
            print("Received:",rc[1])

            if (rc[0] == RC_SUCCESS):
                err = 0

                cmd = str(rc[1].decode().split()[0]).lower()
                parms = str(rc[1][len(cmd)+1:])
                # Executes the command (first word in the string)
                # And passes the whole string (including command name) to the function
                # globals()['use_variable_as_function_name']() 
                globals()[cmd](parms)
            elif (rc[0] == RC_INVALIDCOMMAND or rc[0] == RC_OUTOFSYNC):
                resync()
                errcount += 1
        except Exception as e:
            errcount += 1
            print("Erro in cmd received:"+str(e))

except KeyboardInterrupt:
    GPIO.cleanup() # cleanup all GPIO
    print("Terminating msxpi-server")
