# External module imports
import RPi.GPIO as GPIO
import time
import subprocess
import urllib2
import mmap
import fcntl,os
import sys
from subprocess import Popen,PIPE,STDOUT
from HTMLParser import HTMLParser
import datetime
import time
import glob
import array
import socket
import errno
import select
import base64
from random import randint

version = "1.0"
build   = "20200720.00000"
TRANSBLOCKSIZE = 1024
CRC = 0xAA

# Pin Definitons
csPin   = 21
sclkPin = 20
mosiPin = 16
misoPin = 12
rdyPin  = 25

SPI_SCLK_LOW_TIME = 0.0001
SPI_SCLK_HIGH_TIME = 0.0001

GLOBALRETRIES       =    5
SPI_INT_TIME        =    3000
PIWAITTIMEOUTOTHER  =    120     # seconds
PIWAITTIMEOUTBIOS   =    60      # seconds
SYNCTIMEOUT         =    5
BYTETRANSFTIMEOUT   =    5
SYNCTRANSFTIMEOUT   =    3
STARTTRANSFER       = 0xA0
SENDNEXT            = 0xA1
ENDTRANSFER         = 0xA2
RESEND              = 0XA3
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
RC_SUCCNOSTD        =    0XEB
RC_FAILNOSTD        =    0XEC
RC_PROGERROR        =    0xED
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

def init_spi_bitbang():
# Pin Setup:
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(csPin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(sclkPin, GPIO.OUT)
    GPIO.setup(mosiPin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(misoPin, GPIO.OUT)
    GPIO.setup(rdyPin, GPIO.OUT)

def tick_sclk():
    GPIO.output(sclkPin, GPIO.HIGH)
    #time.sleep(SPI_SCLK_HIGH_TIME)
    GPIO.output(sclkPin, GPIO.LOW)
    #time.sleep(SPI_SCLK_LOW_TIME)

def send_byte_sec(byte_out):
    rc = RESEND
    while rc != ENDTRANSFER:
        send_byte(byte_out)
        send_byte(byte_out^CRC)
        rc =receive_byte()


def send_byte(byte_out):

    GPIO.output(misoPin, GPIO.HIGH)
    while(GPIO.input(csPin)):
        pass

    tick_sclk()
    for bit in [0x80,0x40,0x20,0x10,0x8,0x4,0x2,0x1]:
        if (byte_out & bit):
            GPIO.output(misoPin, GPIO.HIGH)
        else:
            GPIO.output(misoPin, GPIO.LOW)
        GPIO.output(sclkPin, GPIO.HIGH)
        GPIO.output(sclkPin, GPIO.LOW)

    # tick rdyPin once to flag to MSXPi that data is in the GPIO pins
    GPIO.output(rdyPin, GPIO.LOW)
    GPIO.output(rdyPin, GPIO.HIGH)
    GPIO.output(misoPin, GPIO.LOW)

def receive_byte_sec():
    rc = RESEND
    while rc == RESEND:
        b1 = receive_byte()
        b2 = receive_byte()

        if b1^CRC == b2:
            rc = ENDTRANSFER
            send_byte(ENDTRANSFER)
        else:
            send_byte(RESEND)

    return b1

def receive_byte():
    byte_in = 0

    GPIO.output(misoPin, GPIO.HIGH)
    while(GPIO.input(csPin)):
        pass

    tick_sclk()
    for bit in [0x80,0x40,0x20,0x10,0x8,0x4,0x2,0x1]:
        GPIO.output(sclkPin, GPIO.HIGH)    
        if GPIO.input(mosiPin):
            byte_in |= bit
        GPIO.output(sclkPin, GPIO.LOW)

    # tick rdyPin once to flag to MSXPi that transfer is completed
    GPIO.output(rdyPin, GPIO.LOW)
    GPIO.output(rdyPin, GPIO.HIGH)
    GPIO.output(misoPin, GPIO.LOW)

    return byte_in

def sendstdmsg(message):
    return senddatablock(message,0,len(message))

def recvdatablock(sizelimit=65535):
    buf = bytearray()
    crc = 0
    rc = RC_FAILED

    try:
        # Read blocksize to transfer
        dsL = receive_byte()
        dsM = receive_byte()
        blocksize = dsL + 256 * dsM
        
        if blocksize <= sizelimit:
            rc = RC_SUCCESS
            #print("recvdatablock:Received blocksize =",blocksize)
            while(blocksize>0):
                mymsxbyte = receive_byte()
                buf.append(mymsxbyte)
                crc ^= mymsxbyte
                blocksize = blocksize - 1

            # Receive the CRC calculated by the MSX 
            msxcrc = receive_byte()
            if (msxcrc != crc):
                rc = RC_CRCERROR
    except (RuntimeError, TypeError, NameError):
        rc = RC_PROGERROR
        print("Error:",hex(rc))

    try:
        # Send the Return code for MSX
        send_byte(rc)
    except (RuntimeError, TypeError, NameError):
        rc = RC_PROGERROR
        print("Error:",hex(rc))

    print("recvdatablock:exiting with rc = ",hex(rc))
    return [rc,buf]

def senddatablock(buf,initpos,blocksize):
    bytecounter = 0
    crc = 0
    rc = RC_SUCCESS

    try:
        send_byte((blocksize) % 256)
        send_byte((blocksize) / 256)
        #print("senddatablock: blocksize is ", blocksize)
        while(blocksize > 0):
            byte_out = ord(buf[initpos+bytecounter])
            send_byte(byte_out)
            crc ^= byte_out
            bytecounter += 1
            blocksize = blocksize - 1

        #print("senddatablock:Expecting to read CRC")
        # Receive the CRC calculated by the MSX 
        msxcrc = receive_byte()
        if (msxcrc != crc):
            print("senddatablock:wrong crc")
            rc = RC_CRCERROR

        # Send the Return code for MSX
        #print("senddatablock:Sending RC",hex(rc))
        send_byte(rc)

    except (RuntimeError, TypeError, NameError):
        rc = RC_PROGERROR

    return rc

def ploadr(basepath, file):
    rc = RC_SUCCESS

    print("ploadr: checking file path")
    if (file.strip() <> ''):
        fpath = getpath(basepath, file)
        # local file?
        if (fpath[0] < 2):
            try:
                fh = open(str(fpath[1]), 'rb')
                buf = fh.read()
                fh.close()
            except IOError as e:
                rc = RC_FAILED
                print "Error opening file:",e
                sendstdmsg("Pi:" + str(e))
        #Remote file
        else:
            try:
                buf = urllib2.urlopen(fpath[1].decode()).read()
            except urllib2.HTTPError as e:
                rc = RC_FAILED
                print "ploadr:http error "+ str(e)
                sendstdmsg("Pi:" + str(e))
            except:
                rc = RC_FAILED
                print "ploadr:http unknow error"
                sendstdmsg("Pi:Error unknow downloading file")
        if (rc == RC_SUCCESS):
            print("ploadr:Found rom - checking contents")
            if (buf[0]=='A' and buf[1]=='B'):
                fh = open(RAMDISK+'/msxpi.tmp', 'wb')
                fh.write(buf)
                fh.flush()
                fh.close()
                send_byte(RC_SUCCNOSTD)
                print "ploadr:Calling senddatablock.msx "
                GPIO.cleanup()
                cmd = "sudo " + RAMDISK + "/senddatablock.msx " + RAMDISK + "/msxpi.tmp"
                print(cmd)
                p = subprocess.call(cmd, shell=True)
                GPIO.setwarnings(False)
                init_spi_bitbang()
                GPIO.output(rdyPin, GPIO.HIGH)
                GPIO.output(misoPin, GPIO.LOW)
                sendstdmsg("Pi:Ok\n")
            else:
                print "pload:not a ROM file"
                rc = RC_FAILED
                sendstdmsg("Pi:Error - not a ROM file")
    else:
        print "pload:syntax error in command"
        rc = RC_FAILED
        sendstdmsg("Pi:Missing parameters.\nSyntax:\nploadrom file|url <A:>|<B:>file")
                   
    #print "pload:Exiting with rc = ",hex(rc)
    return rc

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

def pcd(basepath, path):
    rc = RC_FAILED
    newpath = basepath
    
    #print "pcd:starting basepath:path=",basepath + ":" + path

    if (path == '' or path.strip() == "."):
        send_byte(rc)
        sendstdmsg(basepath+'\n')
    elif (path.strip() == ".."):
        rc = RC_SUCCESS
        newpath = basepath.rsplit('/', 1)[0]
        if (newpath == ''):
            newpath = '/'
        send_byte(rc)
        sendstdmsg(str(newpath+'\n'))
    else:
        #print "pcd:calling getpath"
        urlcheck = getpath(basepath, path)
        newpath = urlcheck[1]
        #print "pcd:getpath returned:",newpath
        if (newpath[:4] == "http" or \
            newpath[:3] == "ftp" or \
            newpath[:3] == "nfs" or \
            newpath[:3] == "smb"):
            rc = RC_SUCCESS
            send_byte(rc)
            sendstdmsg(str(newpath+'\n'))
        else:
            newpath = str(newpath) #[:len(newpath)-1])
            #print "newpath=",type(newpath),len(newpath)
            if (os.path.isdir(newpath)):
                rc = RC_SUCCESS
                send_byte(rc)
                sendstdmsg(newpath+'\n')
            elif (os.path.isfile(str(newpath))):
                send_byte(rc)
                sendstdmsg("Pi:Error - not a folder")
            else:
                send_byte(rc)
                sendstdmsg("Pi:Error - path not found")
    
    #print "pcd:newpath =",newpath
    #print "pcd:Exiting rc:",hex(rc)
    return [rc, newpath]

def pset(psetvar, cmd):
    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)

    rc = RC_SUCCESS
    buf = "Pi:Error\nSyntax: pset set <var> <value>"
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
                buf = "Pi:Erro setting parameter"

    sendstdmsg(buf)
    #senddatablock(True,buf,0,len(buf))
    #print "pset:Exiting rc:",hex(rc)
    rc_text = psetvar[index][0];
    return rc,rc_text


def readf_tobuf(fpath,buf,ftype):
    buffer = bytearray()
    rc = RC_SUCCESS
    if (ftype < 2):
        #print "local file"
        fh = open(fpath,'rb')
        buf = fh.read()
        fh.close()
        errmgs = "Pi:OK\n"
    else:
        #print "readf_tobuf:network file:",fpath
        req = urllib2.Request(url=fpath)
        
        try:
            getf = urllib2.urlopen(req)
            #print "http code:",getf.getcode()
            
            if (getf.getcode() == 200):
                buffer = getf.read()
                rc = RC_SUCCESS
                errmgs = "Pi:Success"
            else:
                errmgs = "Pi:http error "+str(getf.getcode())
                #print "info:",getf.info()
                #print "http code:",getf.getcode()
        except urllib2.URLError as e:
            rc = RC_FAILED
            errmgs = "Pi:" + str(e)
        except:
            rc = RC_FAILED
            errmgs = "Pi:Error accessing network file"

    #print "readf_tobuf:Exiting with rc:",hex(rc)
    return [rc, errmgs, buffer]

def pwifi(cmd1,wifissid,wifipass):
    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)

    rc = RC_FAILED
    cmd=cmd1.decode().strip()

    if (len(cmd)==0):
        #print("Pi:Error\nSyntax: pwifi display | set")
        prun("echo Syntax: pwifi display \| set")
    elif (cmd[:1] == "s" or cmd[:1] == "S"):
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
    
    print "pwifi:Exiting with rc=",hex(rc)
    return rc

def prun(cmd):
    rc = RC_SUCCESS
    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)
    #print("prun:running command")
    if (cmd.strip() == '' or len(cmd.strip()) == 0):
        send_byte(RC_FAILED)
        sendstdmsg("Syntax: prun <command> <::> command\nTo pipe a command to other, use :: instead of |")
        rc = RC_FAILED
    else:
        cmd = cmd.replace('::','|')
        try:
            p = Popen(cmd.decode(), shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE, close_fds=True)
            buf = p.stdout.read()
            #print("prun:command lengh (hex):",hex(len(buf)))
            if (len(buf) == 0):
                buf = p.stderr.read()
                if  (len(buf) == 0):
                    buf = str("Pi:Error running command "+cmd+'\n')
            send_byte(RC_SUCCESS)
            sendstdmsg(buf)
        except subprocess.CalledProcessError as e:
            print "Error:",buf
            rc = RC_FAILED
            end_byte(RC_FAILED)
            sendstdmsg("Pi:Error\n"+buf+'\n')

    #print "prun:exiting rc:",hex(rc)
    return rc

def pdir(path):
    print("pdir:starting ",path)

    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)
    rc = RC_SUCCESS

    # basepath is global variable
    # Need to extract command line parameters from the passed string
    # Takes only 1st parameter, ignores everything else
    # If no parameters was given, than assume current dirs
    try:
        urlcheck = getpath(basepath, path)
        if (urlcheck[0] == 0 or urlcheck[0] == 1):
            print ("pdir:filesystem access:",urlcheck[1].decode())
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
            #print "pdir:network access:"+urlcheck[1].decode()
            parser = MyHTMLParser()
            try:
                htmldata = urllib2.urlopen(urlcheck[1].decode()).read()
                parser = MyHTMLParser()
                parser.feed(htmldata)
                buf = " ".join(parser.HTMLDATA)
                piexchangebyte(NoTimeOutCheck,RC_SUCCESS)
                rc = senddatablock(buf,0,len(buf))
            except urllib2.HTTPError as e:
                rc = RC_FAILED
                print "pdir:http error "+ str(e)
                sendstdmsg(str(e))
    except Exception as e:
        sendstdmsg('pdir:'+str(e))

    #print "pdir:exiting rc:",hex(rc)
    return rc

def pdate(parms=''):
    now = datetime.datetime.now()
    send_byte(RC_SUCCESS)
    send_byte(now.year & 0xff)
    send_byte(now.year >>8)
    send_byte(now.month)
    send_byte(now.day)
    send_byte(now.hour)
    send_byte(now.minute)
    send_byte(now.second)
    send_byte(0)
    return sendstdmsg('Pi:Ok\n')

def pplay(parms):

    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)

    rc = RC_SUCCESS
    
    cmd = "bash " + RAMDISK + "/pplay.sh PPLAY "+parms+" >" + RAMDISK + "/msxpi.tmp"
    cmd = str(cmd)
    
    print "pplay:starting command:len:",cmd,len(cmd)

    try:
        p = subprocess.call(cmd, shell=True)
        buf = msxdos_inihrd(RAMDISK + "/msxpi.tmp")
        if (buf == RC_FAILED):
            send_byte(RC_FAILED)
            sendstdmsg("Pi:Error opening file\n")
        else:
            end_byte(rc)
            sendstdmsg(buf)
    except subprocess.CalledProcessError as e:
        print "pplay:Error:",p
        rc = RC_FAILED
        send_byte(rc)
        sendstdmsg("Pi:Error\n"+str(e))
    
    #print "pplay:exiting rc:",hex(rc)
    return rc

def file_upload(buf,blocksize=512):

    fileidx = 0
    prevfileidx = 0
    
    filesize = len(buf)

    while (fileidx < filesize):
        GPIO.output(misoPin, GPIO.LOW)

        if blocksize > filesize - fileidx:
            thisblocksize = filesize - fileidx
        else:
            thisblocksize = blocksize

        #print("file_upload:sending STARTTRANSFER")
        send_byte(STARTTRANSFER)
        #print("file_upload:sending block:",thisblocksize)
        rc = senddatablock(buf,fileidx,thisblocksize)
        #print("file_upload: senddatablock returned:",hex(rc))
        #print(buf[fileidx:fileidx+thisblocksize]),
        # if block transmitted without errors, get next block
        # otherwise keep the previous index to resend block
        msxcmd = receive_byte()
        #print("Received MSX command: ",hex(msxcmd))
        if msxcmd == SENDNEXT:
            fileidx += thisblocksize
            #print("file_upload:next block ",fileidx)
            if fileidx >= filesize:
                #print("file_upload:sending ENDTRANSFER")
                send_byte(ENDTRANSFER)
        elif msxcmd == RESEND:
            #fileidx += thisblocksize
            print("file_upload:resending bad block")
        else:
            print("file_upload:Out of sync")


def dos83format(fname):
    name = '        '
    ext = '   '

    finfo = fname.split('.')

    name = str(finfo[0]).ljust(8)
    if len(finfo) == 2:
        ext = str(finfo[1]).ljust(3)
    
    #print("dos83format:",name+ext)

    return name+ext


def ini_fcb(fname):
    #print("init_fcb:",fname)

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
    send_byte(msxdrive)
    for i in range(0,11):
        send_byte(ord(msxfcbfname[i]))
        #print(msxfcbfname[i]),
    

def pcopy(parms):

    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)
    #print("pcopy:",parms)

    try:
    
        fileinfo = parms.split()

        if len(fileinfo) == 1:
            fname_rpi = str(fileinfo[0])
            fname_msx_0 = fname_rpi.split('/')
            fname_msx = str(fname_msx_0[len(fname_msx_0)-1])
        elif len(fileinfo) == 2:
            fname_rpi = str(fileinfo[0])
            fname_msx = str(fileinfo[1])
        else:
            print("Pi:Command line parametrs invalid.")
            send_byte(RC_FAILED)
            sendstdmsg("Pi:Command line parametrs invalid.")


        #print("Pi:Reading file ",fname_rpi)

        with open(fname_rpi, mode='rb') as f:
            buf = f.read()
        
        ini_fcb(fname_msx)
        rc = file_upload(buf)

    except Exception as e:
        print("pcopy:",e)
        send_byte(RC_FAILED)
        sendstdmsg("Pi:"+e)    

def irc(cmd):
    
    global ircsock,allchann,ircmsg

    cmd = 'IRC '+cmd
    ircserver = 'chat.freenode.net'
    ircport = 6667
    channel = "#msx"
    msxpinick =  'msxpi'

    ircconn = False
    print "Processing IRC commands:",cmd
    print(cmd[4:8])
    if (cmd[4:8] == "CONN"):
        print("irc:CONN")
        allchann = []
        #try:
        send_byte(RC_WAIT)
        GPIO.output(misoPin, GPIO.LOW)

        ircsock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        jparm = cmd.split(' ')
        if (len(jparm) != 3):
            ircmsg = "parameters invalid"
            send_byte(RC_SUCCNOSTD)
            print(ircmsg)
        else:
            jnick = jparm[2]
            if (jnick == 'none'):
                jnick = msxpinick
            ircsock.connect((ircserver, ircport))
            ircsock.send(bytes("USER "+ jnick +" "+ jnick +" "+ jnick + " " + jnick + "\n"))
            ircsock.send(bytes("NICK "+ jnick +"\n"))
            ircconn = 1
            ircmsg = 'Connected to '+ircserver
            send_byte(RC_SUCCESS)
            senddatablock(ircmsg,0,len(ircmsg))
            print("irc:CONN -exit = ",ircmsg)
    elif (cmd[4:7] == "MSG"):
        print("irc:MSG")
        if (not ircconn):
            send_byte(RC_WAIT)
            GPIO.output(misoPin, GPIO.LOW)

            ircsock.send(bytes("/msg "+ cmd[5:] + "\n"))
            send_byte(RC_SUCCESS)
        else:
            print("IRC not initilized")
            send_byte(RC_FAILED)
    elif (cmd[4:8] == "JOIN"):
        print("irc:JOIN")
        jparm = cmd.split(' ')
        if (len(jparm) != 3):
            ircmsg = "parameters invalid"
            send_byte(RC_SUCCNOSTD)
        else:
            jchannel = jparm[2]
            if jchannel in allchann:
                #print "Already joined.",jchannel
                send_byte(RC_SUCCNOSTD)
                ircmsg = 'Already joined - setting to current. List of channels:' + str(allchann).replace('bytearray(b','').replace(')','')
                channel = jchannel
            else:
                #print "Joining channel",jchannel
                if (not ircconn):
                    send_byte(RC_WAIT)
                    GPIO.output(misoPin, GPIO.LOW)
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
                    send_byte(RC_SUCCNOSTD)
                else:
                    print("IRC not initilized")
                    send_byte(RC_FAILED)
    elif (cmd[4:8] == "READ"):
        print("irc:READ")
        if (not ircconn):
            ircmsg = ''
            send_byte(RC_WAIT)
            GPIO.output(misoPin, GPIO.LOW)
            ircsock.setblocking(0);
            try:
                ircmsg = ircsock.recv(2048) #.decode("UTF-8")
            except socket.error, e:
                err = e.args[0]
                if err == errno.EAGAIN or err == errno.EWOULDBLOCK:
                    ircmsg = ''
                    send_byte(RC_SUCCNOSTD)
                else:
                    print "Socket error"
                    ircmsg = ''
                    send_byte(RC_FAILNOSTD)
            else:
                ircmsg = ircmsg.strip('\n\r')
                if ircmsg.find("PING :") != -1:
                    ircsock.send(bytes("PONG :pingis\n"))
                    ircmsg = ''
                if ircmsg.find("PRIVMSG") != -1:
                    ircname = ircmsg.split('!',1)[0][1:]
                    ircchidxs = ircmsg.find('PRIVMSG')+8
                    ircchidxe = ircmsg[ircchidxs:].find(':')
                    ircchann = ircmsg[ircchidxs:ircchidxs+ircchidxe-1]
                    if msxpinick in ircchann:
                        ircchann = 'private'
                    ircremmsg = ircmsg[ircchidxs+ircchidxe+1:]
                    ircmsg = '<' + ircchann + '> ' + ircname + ' -> ' + ircremmsg
    
                send_byte(RC_SUCCNOSTD)
            ircsock.setblocking(1);
        else:
            print("IRC not initilized")
            send_byte(RC_FAILED)
    elif (cmd[4:8] == "PART"):
        print("irc:PART")
        if (not ircconn):
            send_byte(RC_WAIT)
            GPIO.output(misoPin, GPIO.LOW)
            ircsock.send(bytes("/part\n"))
            send_byte(RC_SUCCNOSTD)
        else:
            print("IRC not initilized")
            send_byte(RC_FAILED)
    elif (cmd[4:8] == "QUIT"):
        print("irc:QUIT")
        if (not ircconn):
            send_byte(RC_WAIT)
            GPIO.output(misoPin, GPIO.LOW)
            ircsock.send(bytes("/quit\n"))
            ircsock.close()
            send_byte(RC_SUCCNOSTD)
        else:
            print("IRC not initilized")
            send_byte(RC_FAILED)
    elif (cmd[4:10] == "GETRSP"):
        print("irc:GETRSP")
        if (len(ircmsg)==0):
            send_byte(RC_SUCCNOSTD)
        else:
            if (len(ircmsg)>256):
                ircmsg = ircmsg[len(ircmsg)-512:]
            
            send_byte(RC_SUCCESS)
            senddatablock(ircmsg,0,len(ircmsg))
            ircmsg = ''
    elif (cmd[4:9] == "NAMES"):
        print("irc:NAMES")
        if (not ircconn):
            send_byte(RC_WAIT)
            GPIO.output(misoPin, GPIO.LOW)
            ircsock.send(bytes("NAMES " + channel + "\n"))
            ircmsg = ''
            ircmsg = ircmsg + ircsock.recv(2048).decode("UTF-8")
            ircmsg = ircmsg.strip('\n\r')
            ircmsg = "Users on channel " + ircmsg.split('=',1)[1]
            send_byte(RC_SUCCNOSTD)
        else:
            ircmsg = ''
            print("IRC not initilized")
            send_byte(RC_FAILNOSTD)
    else:
        print("irc:others (else)")
        if (not ircconn):
            ircmsg = "PRIVMSG "+ channel +" :" + cmd[4:] +"\n"
            send_byte(RC_WAIT)
            GPIO.output(misoPin, GPIO.LOW)
            ircsock.send(bytes(ircmsg))
            ircmsg = ''
            send_byte(RC_SUCCNOSTD)
        else:
            print("IRC not initilized")
            send_byte(RC_FAILED)

def ptest(parms=False):
    print("ptest:starting reception test")
    send_byte(RC_SUCCESS)

    errors = 0
    n = 0

    for i in range(0,65535):
        dsL = receive_byte()
        dsM = receive_byte()
        m = dsL + 256 * dsM
        if m != n:
            errors += 1
        
        #print(n,m)
        #time.sleep(0.005)

        n += 1
    print("Receiving errors:",errors)

    print("ptest:starting transmission test")
    for i in range(0,65535):
        send_byte((i) % 256)
        send_byte((i) / 256)

# MSX-DOS Support 
# ---------------

def syn(parms=''):
    return RC_SUCCESS

def msxdos_inihrd(filename, access=mmap.ACCESS_WRITE):
    #print "msxdos_inihrd:Starting"
    size = os.path.getsize(filename)
    if (size>0):
        fd = os.open(filename, os.O_RDWR)
        rc = mmap.mmap(fd, size, access=access)
    else:
        rc = RC_FAILED

    return rc

def drives(parms=''):
    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)

    global numdrives

    if numdrives == 0:
        numdrives = 2
    send_byte(numdrives)
    numdrives = 0

def inihrd(init='False'):
    if init != False:
        send_byte(RC_WAIT)
        GPIO.output(misoPin, GPIO.LOW)

    print("inihrd:starting")
    global numdrives,sectorInfo,drive0Data,drive1Data

    if (numdrives<2):
        numdrives += 1

    # Initialize disk system parameters
    sectorInfo = [0,0,0,0]
    numdrives = 0

    # Load the disk images into a memory mapped variable
    drive0Data = msxdos_inihrd('/home/msxpi/disks/msxpiboot.dsk')
    drive1Data = msxdos_inihrd('/home/msxpi/disks/50dicas.dsk')

    print("inihrd:exiting")

def sct(parms=''):

    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)

    print("rds:starting")
    global sectorInfo

    #print("sct: Starting with sectorInfo:",sectorInfo)

    sectorInfo[0] = receive_byte()
    sectorInfo[1] = receive_byte()
    sectorInfo[2] = receive_byte()
    byte_lsb = receive_byte()
    byte_msb = receive_byte()
    sectorInfo[3] = byte_lsb + 256 * byte_msb
    
    #print "sct:deviceNumber=",sectorInfo[0]
    #print "sct:sectors=",sectorInfo[1]
    #print "sct:mediaDescriptor=",sectorInfo[2]
    #print "sct:initialSector=",sectorInfo[3]

# ---------------

def rds(parms=''):
    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)

    #print("rds:starting")
    global drive0Data,drive1Data,sectorInfo

    if sectorInfo[0] == 0:
        driveData = drive0Data
    else:
        driveData = drive1Data

    initbytepos = sectorInfo[3]*512
    finalbytepos = (initbytepos + sectorInfo[1]*512)
    #print "rds:Total bytes to transfer:",finalbytepos-initbytepos
    for t in range(0,3):
        rc = senddatablock(driveData,initbytepos,finalbytepos-initbytepos)
        #print("rds:senddatablock rc is ",hex(rc))
        if rc == RC_SUCCESS:
            break

    #print "msxdos_readsector:exiting rc:",hex(rc)

def wrs(parms=''):
    print("wrs:starting")
    send_byte(RC_WAIT)
    GPIO.output(misoPin, GPIO.LOW)


    global drive0Data,drive1Data,sectorInfo
    
    if sectorInfo[0] == 0:
        driveData = drive0Data
    else:
        driveData = drive1Data

    rc = RC_SUCCESS

    #print "msxdos_writesector:Starting"
    #print "msxdos_readsector:Starting with sectorInfo=",sectorInfo
    #print "msxdos_readsector:deviceNumber=",sectorInfo[0]
    #print "msxdos_readsector:numsectors=",sectorInfo[1]
    #print "msxdos_readsector:mediaDescriptor=",sectorInfo[2]
    #print "msxdos_readsector:initialSector=",sectorInfo[3]
    initbytepos = sectorInfo[3]*512
                                 
    index = 0
    sectorcount = sectorInfo[1]
    # Read data from MSX
    while(sectorcount and rc == RC_SUCCESS):
        #print "Sectors to write:",sectorcount
        for t in range(0,3):
            rc = recvdatablock()
            print("rds:recvdatablock returned")
            if rc == RC_SUCCESS:
                driveData[index+initbytepos:index+initbytepos+len(rc[1])] = str(rc[1])
                index += 512
                sectorcount -= 1
                break

            rc = RC_FAILED

    #print "msxdos_writesector:exiting rc:",hex(rc)

""
""" ============================================================================
    msxpi-server.py
    main program starts here
    ============================================================================
"""

basepath = '/home/msxpi'
MSXPIHOME = "/home/msxpi"
RAMDISK = "/media/ramdisk"
TMPFILE = RAMDISK + "/msxpi.tmp"
numdrives = 0
sectorInfo = []
drive0Data = ''
drive1Data = ''

init_spi_bitbang()
GPIO.output(rdyPin, GPIO.LOW)
GPIO.output(rdyPin, GPIO.HIGH)
GPIO.output(misoPin, GPIO.LOW)
print "GPIO Initialized\n"
print "Starting MSXPi Server Version ",version,"Build",build

inihrd(False)

def receivecommand():
    #return [RC_SUCCESS,"SCT"]
    return recvdatablock(128)


try:
    while True:
        print("st_recvcmd: waiting command")
        rc = receivecommand()
        #print("Received command",rc)

        if (rc[0] == RC_SUCCESS):
            try:
                cmd = str(rc[1].split()[0]).lower()
                parms = str(rc[1][len(cmd)+1:])
                print("Received:",cmd,parms)
                # Executes the command (first word in the string)
                # And passes the whole string (including command name) to the function
                # globals()['use_variable_as_function_name']() 
                globals()[cmd](parms)
            except Exception, e:
                print(e)

except KeyboardInterrupt:
    GPIO.cleanup() # cleanup all GPIO
    print "Terminating msxpi-server"
