# External module imports
import RPi.GPIO as GPIO
import time
import subprocess
import urllib
import mmap
import os
import sys
from subprocess import Popen,PIPE,STDOUT
from HTMLParser import HTMLParser

version = 0.1
build   = 20171110

# Pin Definitons
csPin   = 21
sclkPin = 20
mosiPin = 16
misoPin = 12
rdyPin  = 25

SPI_SCLK_LOW_TIME = 0.001
SPI_SCLK_HIGH_TIME = 0.001

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
RC_INFORESPONSE     =    0xE8
RC_WAIT             =    0xE9
RC_READY            =    0xEA
RC_SUCCNOSTD        =    0XEB
RC_FAILNOSTD        =    0XEC
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
TMPFILE = "/tmp/msxpi.tmp"

def init_spi_bitbang():
# Pin Setup:
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(csPin, GPIO.IN, pull_up_down=GPIO.PUD_UP)
    GPIO.setup(sclkPin, GPIO.OUT)
    GPIO.setup(mosiPin, GPIO.IN, pull_up_down=GPIO.PUD_DOWN)
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
    tick_sclk();
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

    tick_sclk();
    #print "transfer_byte:received",hex(byte_in),":",chr(byte_in)
    return byte_in

def piexchangebyte(checktimeout,mypibyte):
    time_start = time.time()
    timeout = False
    rc = RC_SUCCESS
    
    GPIO.output(rdyPin, GPIO.HIGH)
    #GPIO.wait_for_edge(csPin, GPIO.FALLING)
    if (checktimeout):
        while(GPIO.input(csPin)):
            if (time.time() - time_start > BYTETRANSFTIMEOUT):
                timeout = True
    else:
        while(GPIO.input(csPin)):
            ()

    mymsxbyte = SPI_MASTER_transfer_byte(mypibyte);
    GPIO.output(rdyPin, GPIO.LOW)

    if (timeout):
        rc = RC_TIMEOUT

    #print "piexchangebyte: received:",hex(mymsxbyte)
    return [rc,mymsxbyte]

def sendstdmsg(rc, message):
    piexchangebyte(NoTimeOutCheck,rc)
    return senddatablock(TimeOutCheck,message,0,len(message),True);

def recvdatablock(timeoutFlag):
    buffer = bytearray()
    bytecounter = 0
    crc = 0
    rc = RC_SUCCESS
    
    mymsxbyte = piexchangebyte(timeoutFlag,SENDNEXT)
    if (mymsxbyte[1] != SENDNEXT):
        print "recvdatablock:Out of sync with MSX, waiting SENDNEXT, received",hex(mymsxbyte[0]),hex(mymsxbyte[1])
        rc = RC_OUTOFSYNC;
    else:
        dsL = piexchangebyte(NoTimeOutCheck,SENDNEXT)
        dsM = piexchangebyte(NoTimeOutCheck,SENDNEXT)
        datasize = dsL[1] + 256 * dsM[1]
        
        #print "recvdatablock:Received blocksize =",datasize;
        while(datasize>bytecounter and rc == RC_SUCCESS):
            mymsxbyte = piexchangebyte(TimeOutCheck,SENDNEXT)
            if (mymsxbyte[0] == RC_SUCCESS):
                #print "recvdatablock:Received byte:",chr(mymsxbyte[1]);
                buffer.append(mymsxbyte[1])
                crc ^= mymsxbyte[1]
                bytecounter += 1
            else:
                #print "recvdatablock:Error during transfer"
                rc = RC_TIMEOUT

    if (rc == RC_SUCCESS):
        #print "crc = ",crc
        mymsxbyte = piexchangebyte(NoTimeOutCheck,crc)
        if (mymsxbyte[1] != crc):
            rc = RC_CRCERROR
        #else:
            #print "recvdatablock:CRC verified"

    #print "recvdatablock:exiting with rc = ",hex(rc)
    return [rc,buffer]

def secrecvdata(buffer,initbytepos):
    rc = RC_SUCCESS
    
    #print "secrecvdata:starting"
    
    msxbyte = piexchangebyte(TimeOutCheck,SENDNEXT)
    if (msxbyte[1]==SENDNEXT):
        bytel = piexchangebyte(NoTimeOutCheck,SENDNEXT)[1]
        bytem = piexchangebyte(NoTimeOutCheck,SENDNEXT)[1]
        filesize = bytel + (bytem * 256)

        blocksize = filesize
        if (filesize>512):
            blocksize = 512
        
        index = 0
        retries = 0
        while(index<filesize):
            retries = 0
            rc = RC_UNDEFINED
            while(retries < GLOBALRETRIES and rc <> RC_SUCCESS):
                datablock = recvdatablock(NoTimeOutCheck)
                rc = datablock[0]
                retries += 1
            
            if(retries>GLOBALRETRIES):
                break

            buffer[index+initbytepos:index+initbytepos+len(datablock[1])] = str(datablock[1])
            index += 512
            
            if (filesize - index > 512):
                blocksize = 512
            else:
                blocksize = filesize - index
    
        if(retries>=GLOBALRETRIES):
            print "secrecvdata:Transfer interrupted due to CRC error"
            rc = RC_CRCERROR
        #else:
            #print "secrecvdata:successful"
                
    else:
        rc = RC_FAILNOSTD
        print "secrecvdata:out of sync"
        piexchangebyte(TimeOutCheck,rc)

    #print "secrecvdata:Exiting with rc = ",hex(rc)
    return rc

def senddatablock(checktimeout,buffer,initpos,datasize,sendsize):
    bytecounter = 0
    crc = 0
    rc = RC_SUCCESS
    
    mymsxbyte = piexchangebyte(TimeOutCheck,SENDNEXT)
    if (mymsxbyte[1] != SENDNEXT):
        print "senddatablock:Out of sync with MSX, waiting SENDNEXT, received",mymsxbyte
        rc = RC_OUTOFSYNC;
    else:
        if (sendsize):
            #print "senddatablock:Sending blocksize ",datasize
            piexchangebyte(NoTimeOutCheck,datasize % 256)
            piexchangebyte(NoTimeOutCheck,datasize / 256)
    
        while(datasize>bytecounter and rc == RC_SUCCESS):
            #mypibyte = ord(buffer[bytecounter])
            mypibyte = ord(buffer[initpos+bytecounter])
            #print "senddatablock:",mypibyte
            rc = mymsxbyte[0]
            mymsxbyte = piexchangebyte(TimeOutCheck,mypibyte)
            if (rc == RC_SUCCESS):
                #print "senddatablock:byte sent successfully"
                crc ^= mypibyte
                bytecounter += 1
            else:
                print "senddatablock:Error during transfer:",hex(rc)
                rc = RC_TIMEOUT

    if (rc == RC_SUCCESS):
        mymsxbyte = piexchangebyte(NoTimeOutCheck,crc)
        #print "senddatablock:CRC local:remote = ",crc,":",mymsxbyte[1]
        if (mymsxbyte[1] != crc):
            rc = RC_CRCERROR;
        #else:
        #    print "senddatablock:CRC verified"

    #print "senddatablock:Exiting with rc=",hex(rc)
    return rc

def secsenddata(buffer, initpos, filesize):
    rc = RC_SUCCESS
    
    #print "secsenddata:starting transfer for",filesize,"bytes"
    
    msxbyte = piexchangebyte(TimeOutCheck,SENDNEXT)
    
    if (msxbyte[1]==SENDNEXT):
        piexchangebyte(NoTimeOutCheck,filesize % 256)
        piexchangebyte(NoTimeOutCheck,filesize / 256)
        
        blocksize = filesize
        if (filesize>512):
            blocksize = 512

        index = 0
        retries = 0
        
        while(index<filesize):
            retries = 0
            rc = RC_UNDEFINED
            lastindex = index+blocksize
                                
            while(retries < GLOBALRETRIES and rc <> RC_SUCCESS):
                #print "secsenddata:initpos=",index,"endpos=",lastindex,"retry=",retries
                rc = senddatablock(TimeOutCheck,buffer,index+initpos,blocksize,True)
                retries += 1

            if(retries>=GLOBALRETRIES):
                break
            else:
                index += 512
                if (filesize - index > 512):
                    blocksize = 512
                else:
                    blocksize = filesize - index
                                                                
        if(retries>=GLOBALRETRIES):
            print "secsenddata:Transfer interrupted due to CRC error"
            rc = RC_CRCERROR
        #else:
            #print "secsenddata:successful"
    else:
        rc = RC_FAILNOSTD
        #print "secsenddata:out of sync"
        piexchangebyte(TimeOutCheck,rc)

    #print "secsenddata:Exiting with rc = ",hex(rc)
    return rc

def prun(cmd):
    rc = RC_SUCCESS
    print "prun:starting command:",cmd
    piexchangebyte(NoTimeOutCheck,RC_WAIT);
    try:
        p = Popen(str(cmd), shell=True, stdin=PIPE, stdout=PIPE, stderr=STDOUT, close_fds=True)
        buf = p.stdout.read()
        print "prun:result is ",buf
        print "prun:Sending output to MSX. Size is:",len(buf)
        sendstdmsg(rc,buf);
    except subprocess.CalledProcessError as e:
        print "Error:",buf
        rc = RC_FAILED
        sendstdmsg(rc,"Pi:Error\n"+buf)

    #print "prun:exiting rc:",hex(rc)
    return rc;

def ploadr(basepath, file):
    rc = RC_SUCCESS
    
    #print "pload:starting"
    
    msxbyte = piexchangebyte(NoTimeOutCheck,RC_WAIT)
    if (msxbyte[1]==SENDNEXT):
        fpath = getpath(basepath, file)
        #print "ploadr:fpath =",fpath[1]
        if (len(fpath[1]) > 0 and fpath[1] <> ''):
            try:
                fh = open(str(fpath[1]), 'rb')
                buf = fh.read()
                fh.close()
                
                #print "pload:len of buf:",len(buf)
                
                if (buf[0]=='A' and buf[1]=='B'):
                    msxbyte = piexchangebyte(NoTimeOutCheck,RC_SUCCNOSTD)
                    if (msxbyte[1]==SENDNEXT):
                        
                        msxbyte = piexchangebyte(NoTimeOutCheck,STARTTRANSFER)
                        if (msxbyte[1]==STARTTRANSFER):
                            rc = senddatablock(True,buf,0,len(buf),True)
                        if (rc == RC_SUCCESS):
                            #print "pload:successful"
                            sendstdmsg(rc,"Pi:Ok")
                        else:
                            rc = RC_FAILED
                            sendstdmsg(rc,"pload:out of sync in STARTTRANSFER")
    
            except IOError:
                rc = RC_FAILED
                print "Error opening file"
                sendstdmsg(rc,"Pi:Error opening file")
        else:
            print "pload:syntax error in command"
            rc = RC_FAILED
            sendstdmsg(rc,"Pi:Missing parameters.\nSyntax:\nploadrom file|url <A:>|<B:>file")

    #print "pload:Exiting with rc = ",hex(rc)
    return rc

def getpath(basepath, path):
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
        newpath = basepath + "/" + path.strip()
    elif (basepath.startswith('http') or \
          basepath.startswith('ftp') or \
          basepath.startswith('nfs') or \
          basepath.startswith('smb')):
        urltype = 3 # this is an relative network path
        newpath = basepath + "/" + path.strip()

    #print "fullpath =",newpath
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

def pdir(basepath, path):
    rc = RC_SUCCESS
    #print "pdir:starting"

    msxbyte = piexchangebyte(False,RC_WAIT)
    if (msxbyte[1]==SENDNEXT):
        urlcheck = getpath(basepath, path)
        print "File type =",urlcheck[0]
        if (urlcheck[0] == 0 or urlcheck[0] == 1):
            cmd = "ls -l " +  urlcheck[1]
            cmd = cmd.decode().split(" ")
            buf = subprocess.check_output(cmd)
            piexchangebyte(NoTimeOutCheck,RC_SUCCESS);
            rc = senddatablock(TimeOutCheck,buf,0,len(buf),True);
        else:
            #print "pdir:network access:"+urlcheck[1].decode()
            parser = MyHTMLParser()
            htmldata = urllib.urlopen(urlcheck[1].decode()).read()
            parser = MyHTMLParser()
            parser.feed(htmldata)
            buf = " ".join(parser.HTMLDATA)
            print buf
            piexchangebyte(NoTimeOutCheck,RC_SUCCESS);
            rc = senddatablock(TimeOutCheck,buf,0,len(buf),True);
    else:
        rc = RC_FAILNOSTD
        print "pdir:out of sync in RC_WAIT"

    #print "pdir:exiting rc:",hex(rc)
    return rc;

def pcd(basepath, path):
    rc = RC_SUCCESS
    #print "pcd:starting"
    
    msxbyte = piexchangebyte(False,RC_WAIT)
    if (msxbyte[1]==SENDNEXT):
        urlcheck = getpath(basepath, path)
        newpath = urlcheck[1]
        #sendstdmsg(rc,bytearray(newpath))
        sendstdmsg(rc,"Pi:OK")
    else:
        rc = RC_FAILNOSTD
        print "pcd:out of sync in RC_WAIT"
    
    #print "pcd:Exiting rc:",hex(rc)
    return [rc, newpath];

def pset(psetvar, attrs):
    rc = RC_SUCCESS
    #print "pset: Starting"
    #msxbyte = piexchangebyte(False,RC_WAIT)
    #if (msxbyte[1]==SENDNEXT):
    s = str(psetvar)
    buf = s.replace(", ",",").replace("[[","").replace("]]","").replace("],","\n").replace("[","").replace(",","=").replace("'","")
    #piexchangebyte(False,RC_SUCCESS)
    senddatablock(True,buf,0,len(buf),True);
    #else:
    #rc = RC_FAILNOSTD
    #print "pcd:out of sync in RC_WAIT"
    
    #print "pset:Exiting rc:",hex(rc)
    return rc


def readf_tobuf(fpath,buf,ftype):
    rc = RC_SUCCESS
    if (ftype < 2):
        print "local file"
        fh = open(fpath,'rb')
        buf = fh.read()
        fh.close()
        errmgs = "Pi:OK"
    else:
        req = urllib2.Request(url)
        
        try:
            getf = urllib2.urlopen(req)
            if (getf == 200):
                buf = getf.read()
                rc = RC_SUCCESS
                errmgs = "Pi:Success"
            else:
                errmgs = "Pi:http error "+getf.getcode()
        except urllib2.URLError as e:
            rc = RC_FAILED
            errmgs = "Pi:" + e
        except:
            rc = RC_FAILED
            errmgs = "Pi:Error accessing network file"

    return [rc, errmgs]

def pplay(cmd):
    rc = RC_SUCCESS
    
    cmd = "bash /home/pi/msxpi/pplay.sh PPLAY "+cmd+" >/tmp/msxpi.tmp"
    cmd = str(cmd)
    
    print "pplay:starting command:len:",cmd,len(cmd)

    piexchangebyte(NoTimeOutCheck,RC_WAIT);
    try:
        p = subprocess.call(cmd, shell=True)
        print "p = ",p
        buf = msxdos_inihrd("/tmp/msxpi.tmp")
        if (buf == RC_FAILED):
            sendstdmsg(RC_SUCCESS,"Pi:Ok\n")
        else:
            sendstdmsg(rc,buf);
    except subprocess.CalledProcessError as e:
        print "pplay:Error:",p
        rc = RC_FAILED
        sendstdmsg(rc,"Pi:Error\n"+str(e))
    
    #print "pplay:exiting rc:",hex(rc)
    return rc;

def uploaddata(buffer, totalsize, index):
    print "uploaddata:Starting"

    msxbyte = piexchangebyte(TimeOutCheck, STARTTRANSFER)
    if (msxbyte[1] == STARTTRANSFER):
        print "uploaddata:Receiving blocksize"
        #read blocksize, MAXIMUM 65535 KB
        msxblocksize = piexchangebyte(NoTimeOutCheck,SENDNEXT)[1] + 256 * piexchangebyte(NoTimeOutCheck, SENDNEXT)[1]
        myblocksize = msxblocksize;
    
        #Now verify if has finished transfering data
        if (index*msxblocksize >= totalsize):
            piexchangebyte(NoTimeOutCheck, ENDTRANSFER)
            rc = ENDTRANSFER
        else:
            piexchangebyte(NoTimeOutCheck, SENDNEXT)

            print "uploaddata:Received block size:",msxblocksize
            if (totalsize <= index*msxblocksize+msxblocksize):
                myblocksize = totalsize - (index*msxblocksize)

            print "uploaddata:Sent possible block size:",myblocksize
            piexchangebyte(NoTimeOutCheck, myblocksize % 256)
            piexchangebyte(NoTimeOutCheck, myblocksize / 256)
            
            crc = 0
            bytecounter = 0
    
            print "uploaddata: Loop to send block\n"
            while(bytecounter<myblocksize):
                #print "Byte pos:",index*myblocksize + bytecounter
                mypibyte = buffer[index*myblocksize + bytecounter]
                piexchangebyte(TimeOutCheck, ord(mypibyte))
                crc ^= ord(mypibyte)
                bytecounter += 1
                                
            msxbyte = piexchangebyte(NoTimeOutCheck, crc)
            if (msxbyte[1] == crc):
                rc = RC_SUCCESS
            else:
                rc = RC_CRCERROR

    else:
        rc = RC_OUTOFSYNC
        print "uploaddata:Error - out of sync. Received",hex(msxbyte[1])

    print "upladodata:Exiting with rc=",hex(rc)
    return rc

"""
    function to initialize disk image into a memory mapped variable
"""
def msxdos_inihrd(filename, access=mmap.ACCESS_WRITE):
    #print "msxdos_inihrd:Starting"
    size = os.path.getsize(filename)
    if (size>0):
        fd = os.open(filename, os.O_RDWR)
        rc = mmap.mmap(fd, size, access=access)
    else:
        rc = RC_FAILED

    return rc

"""
    Receive sector data from MSX and store locally
    unsigned char deviceNumber;
    unsigned char numsectors;
    unsigned char mediaDescriptor;
    int           initialSector;
    } DOS_SectorStruct;
"""
def msxdos_secinfo(sectorInfo):
    rc = RC_SUCCESS
    #print "msxdos_secinfo: Starting with sectorInfo:",sectorInfo
    mymsxbyte = piexchangebyte(TimeOutCheck,SENDNEXT)
    if (mymsxbyte[1] == SENDNEXT):
        sectorInfo[0] = piexchangebyte(NoTimeOutCheck,SENDNEXT)[1]
        sectorInfo[1] = piexchangebyte(NoTimeOutCheck,SENDNEXT)[1]
        sectorInfo[2] = piexchangebyte(NoTimeOutCheck,SENDNEXT)[1]
        byte_lsb = piexchangebyte(NoTimeOutCheck,SENDNEXT)[1]
        byte_msb = piexchangebyte(NoTimeOutCheck,SENDNEXT)[1]
        sectorInfo[3] = byte_lsb + 256 * byte_msb;
    else:
        print "msxdos_secinfo:sync_transf error"
        rc = RC_OUTOFSYNC;
    
    #print "msxdos_secinfo:deviceNumber=",sectorInfo[0]
    #print "msxdos_secinfo:sectors=",sectorInfo[1]
    #print "msxdos_secinfo:mediaDescriptor=",sectorInfo[2]
    #print "msxdos_secinfo:initialSector=",sectorInfo[3]
    #print "msxdos_secinfo:exiting rc:",hex(rc)
    return rc;

""" 
    msxdos_readsector
"""
def msxdos_readsector(driveData, sectorInfo):
    initbytepos = sectorInfo[3]*512
    finalbytepos = (initbytepos + sectorInfo[1]*512)
    #print "msxdos_readsector:Total bytes to transfer:",finalbytepos-initbytepos
    rc = secsenddata(driveData,initbytepos,finalbytepos-initbytepos)
    #print "msxdos_readsector:exiting rc:",hex(rc)

""" 
    msxdos_writesector
"""

def msxdos_writesector(driveData, sectorInfo):
    rc = RC_SUCCESS
    #print "msxdos_writesector:Starting"
    #print "msxdos_readsector:Starting with sectorInfo=",sectorInfo
    #print "msxdos_readsector:deviceNumber=",sectorInfo[0]
    #print "msxdos_readsector:numsectors=",sectorInfo[1]
    #print "msxdos_readsector:mediaDescriptor=",sectorInfo[2]
    #print "msxdos_readsector:initialSector=",sectorInfo[3]
    initbytepos = sectorInfo[3]*512
                                 
    index = 0;
    sectorcount = sectorInfo[1]
    # Read data from MSX
    while(sectorcount and rc == RC_SUCCESS):
        #print "Sectors to write:",sectorcount
        rc = secrecvdata(driveData,index+initbytepos)
        index += 512
        sectorcount -= 1

    #print "msxdos_writesector:exiting rc:",hex(rc)

""" ============================================================================
    msxpi-server.py
    main program starts here
    ============================================================================
"""
print "GPIO Initialized\n"
print "Starting MSXPi Server Version ",version,"Build",build

psetvar = [['PATH','/home/msxpi'], \
           ['DRIVE0','disks/msxpiboot.dsk'], \
           ['DRIVE1','disks/msxpitools.dsk'], \
           ['WIDTH','80'], \
           ['free',''], \
           ['WIFISSID','MYWIFI'], \
           ['WIFIPWD','MYWFIPASSWORD'], \
           ['DSKTMPL','disks/msxpi_720KB_template.dsk'], \
           ['free',''], \
           ['free',''] \
           ]

# Initialize disk system parameters
sectorInfo = [0,0,0,0]
numdrives = 0

# Load the disk images into a memory mapped variable
drive0Data = msxdos_inihrd(psetvar[1][1])
drive1Data = msxdos_inihrd(psetvar[2][1])

appstate = st_init
pcopystat2 = 0
pcopyindex = 0

init_spi_bitbang()
GPIO.output(rdyPin, GPIO.LOW)

try:
    while (appstate != st_shutdown):
        print "st_recvcmd: waiting command"
        rc = recvdatablock(NoTimeOutCheck);

        if (rc[0] == RC_SUCCESS):
            cmd = rc[1]
            print "Received command ",cmd
            
            """ 
            MSX-DOS Driver routines 
            """
            if (cmd[:3] == "SCT"):
                msxdos_secinfo(sectorInfo)
            elif (cmd[:3] == "RDS"):
                if (sectorInfo[0] == 0):
                    msxdos_readsector(drive0Data,sectorInfo)
                else:
                    msxdos_readsector(drive1Data,sectorInfo)
            elif (cmd[:3] == "WRS"):
                if (sectorInfo[0] == 0):
                    msxdos_writesector(drive0Data,sectorInfo)
                else:
                    msxdos_writesector(drive1Data,sectorInfo)
            elif (cmd[:6] == "INIHRD"):
                if (numdrives<2):
                    numdrives += 1
            elif(cmd[:6] == "DRIVES"):
                piexchangebyte(NoTimeOutCheck,numdrives)
                numdrives = 0
            elif (cmd[:3] == "FMT"):
                piexchangebyte(NoTimeOutCheck,RC_UNDEFINED)
            elif (cmd[:4] == "prun" or cmd[:4] == "PRUN"):
                prun(cmd[5:])
            elif (cmd[:6] == "ploadr" or cmd[:6] == "PLOADR"):
                ploadr(psetvar[0][1],cmd[7:])

            elif (cmd[:4] == "pdir" or cmd[:4] == "PDIR"):
                pdir(psetvar[0][1],cmd[5:])
    
            elif (cmd[:3] == "pcd" or cmd[:3] == "PCD"):
                newpath = pcd(psetvar[0][1],cmd[3:])
                if (newpath[0] == RC_SUCCESS):
                    psetvar[0][1] = str(newpath[1])
                   
            elif (cmd[:4] == "pset" or cmd[:4] == "PSET"):
                pset(psetvar,cmd[5:])

            elif (cmd[:3] == "SYN" or \
                  cmd[:9] == "chkpiconn" or \
                  cmd[:9] == "chkpiconn"):
                piexchangebyte(TimeOutCheck,READY)

            elif (cmd[:5] == "pcopy" or cmd[:5] == "PCOPY"):
                if (pcopystat2==0):
                    args = cmd.decode().split(" ")
                    if (len(args) == 1 or args[1] == ''):
                        print "pcopy:Syntax error"
                        sendstdmsg(RC_FILENOTFOUND,"Pi:Error\nSyntax: pcopy <source file|url> <target file>")
                    elif (len(args) == 2 and args[1] <> ''):
                        srcurl = args[1].split("/")
                        fname = srcurl[len(srcurl)-1]
                    elif (len(args) == 3):
                        fname = args[2]

                    mymsxbyte = piexchangebyte(NoTimeOutCheck, SENDNEXT)
                    if (mymsxbyte[1] == SENDNEXT):
                        rc = senddatablock(True,fname,0,len(fname),True)
                        msxbyte = piexchangebyte(NoTimeOutCheck, RC_WAIT)
                        fpath = getpath(psetvar[0][1],args[1])[1]
                        
                        if (fpath[0] < 2):
                            if (os.path.exists(fpath)):
                                buf = msxdos_inihrd(fpath)
                            else:
                                print "pcopy:error reading file"
                                rc = RC_FAILED
                                sendstdmsg(rc,"RPi:Error reading file")
                                pcopystat2 = 0
                        else:  # network path
                            rcbuf = readf_tobuf(fpath[1],buf,fpath[0])
                            if (rcbuf[0] == RC_SUCCESS):
                                buf = rcbuf[1]
                            else:
                                print "pcopy:error reading acessing network"
                                rc = RC_FAILED
                                sendstdmsg(rc,"RPi:Error acessing network file")
                                pcopystat2 = 0
                        
                        pcopystat2 = 1;
                        pcopyindex = 0;
                        retries = 0;
                        filesize = len(buf)
                        piexchangebyte(NoTimeOutCheck, RC_SUCCESS)
                    else:
                        print "pcopy:sync error"
                else:
                    rc = uploaddata(buf,filesize,pcopyindex)
                    if (rc == ENDTRANSFER):
                        pcopystat2 = 0
                        rc = RC_SUCCESS
                        buf = "Pi:Ok"
                        senddatablock(TimeOutCheck,buf,0,len(buf),True);
                    elif (rc == RC_SUCCESS):
                        pcopyindex += 1
                    elif (rc == RC_CRCERROR and retries < GLOBALRETRIES):
                        retries += 1
                    else:
                        print "pcopy:uploaddata error"
                        pcopystat2 = 0
                          
            elif (cmd[:5] == "pplay" or cmd[:5] == "PPLAY"):
                pplay(cmd[6:])
            else:
                print "Error"
                piexchangebyte(False,RC_FAILNOSTD)

            cmd = ''

except KeyboardInterrupt:
    GPIO.cleanup() # cleanup all GPIO
    print "Terminating msxpi-server"

