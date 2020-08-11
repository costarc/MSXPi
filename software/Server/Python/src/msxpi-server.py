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

version = "0.9.0"
build   = "20200810.00001"
TRANSBLOCKSIZE = 1024

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
RC_CONNERR          =    0xE8
RC_WAIT             =    0xE9
RC_READY            =    0xEA
RC_SUCCNOSTD        =    0XEB
RC_FAILNOSTD        =    0XEC
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

    mymsxbyte = SPI_MASTER_transfer_byte(mypibyte)
    GPIO.output(rdyPin, GPIO.LOW)

    if (timeout):
        rc = RC_TIMEOUT

    #print "piexchangebyte: received:",hex(mymsxbyte)
    return [rc,mymsxbyte]

def sendstdmsg(rc, message):
    piexchangebyte(NoTimeOutCheck,rc)
    return senddatablock(TimeOutCheck,message,0,len(message),True)

def recvdatablock(timeoutFlag):
    buffer = bytearray()
    bytecounter = 0
    crc = 0
    rc = RC_SUCCESS
    
    mymsxbyte = piexchangebyte(timeoutFlag,SENDNEXT)
    if (mymsxbyte[1] != SENDNEXT):
        print "recvdatablock:Out of sync with MSX, waiting SENDNEXT, received rc,msxbyte:",hex(mymsxbyte[0]),hex(mymsxbyte[1])
        rc = RC_OUTOFSYNC
    else:
        dsL = piexchangebyte(NoTimeOutCheck,SENDNEXT)
        dsM = piexchangebyte(NoTimeOutCheck,SENDNEXT)
        datasize = dsL[1] + 256 * dsM[1]
        
        #print "recvdatablock:Received blocksize =",datasize
        while(datasize>bytecounter and rc == RC_SUCCESS):
            mymsxbyte = piexchangebyte(TimeOutCheck,SENDNEXT)
            if (mymsxbyte[0] == RC_SUCCESS):
                #print "recvdatablock:Received byte:",chr(mymsxbyte[1])
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
        print "senddatablock:Out of sync with MSX, waiting SENDNEXT, received",hex(mymsxbyte[0]),hex(mymsxbyte[1])
        rc = RC_OUTOFSYNC
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
            rc = RC_CRCERROR
        #else:
        #    print "senddatablock:CRC verified"

    #print "senddatablock:Exiting with rc=",hex(rc)
    return rc

#   senddatablockC(TimeOutCheck,buffer,index+initpos,blocksize,True)
def senddatablockC(flag1,buf,initpos,size,flag2):
    fh = open(RAMDISK+'/msxpi.tmp', 'wb')
    fh.write(buf[initpos:initpos+size])
    fh.flush()
    fh.close()
    print "senddatablockC:Calling senddatablock.msx:",initpos,size
    cmd = "sudo " + RAMDISK + "/senddatablock.msx " + RAMDISK + "/msxpi.tmp"
    rc = subprocess.call(cmd, shell=True)
    init_spi_bitbang()
    GPIO.output(rdyPin, GPIO.LOW)
    print "Exiting senddatablockC:call returned:",hex(rc)
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
        print "secsenddata:out of sync"
        piexchangebyte(TimeOutCheck,rc)

    #print "secsenddata:Exiting with rc = ",hex(rc)
    return rc

def msxdos_inihrd(filename, access=mmap.ACCESS_WRITE):
    #print "msxdos_inihrd:Starting"
    size = os.path.getsize(filename)
    if (size>0):
        fd = os.open(filename, os.O_RDWR)
        rc = mmap.mmap(fd, size, access=access)
    else:
        rc = RC_FAILED

    return rc

def pdir(path):
    #print("pdir:starting ",path)

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
            #print ("pdir:filesystem access:",urlcheck[1].decode())
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
            send_byte(RC_WAIT)
            #print "pdir:network access:"+urlcheck[1].decode()
            parser = MyHTMLParser()
            try:
                htmldata = urllib2.urlopen(urlcheck[1].decode()).read()
                parser = MyHTMLParser()
                parser.feed(htmldata)
                buf = " ".join(parser.HTMLDATA)
                send_byte(RC_SUCCESS)
                if len(buf) == 0:
                    buf = 'Empty directory'
                rc = senddatablock(buf,0,len(buf))
            except urllib2.HTTPError as e:
                rc = RC_FAILED
                print "pdir:http error "+ str(e)
                send_byte(rc)
                sendstdmsg(str(e))
    except Exception as e:
        send_byte(RC_FAILED)
        print "pdir:http error "+ str(e)
        sendstdmsg('pdir:'+str(e))

    #print "pdir:exiting rc:",hex(rc)
    return rc
    
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

WUPGRP = {'554191119326-1399041454@g.us' : 'MSXBr', '447840924680-1486475091@g.us' :'MSXPi', '447840924680-1515184325@g.us' : 'MSXPiTest'}

# Initialize disk system parameters
sectorInfo = [0,0,0,0]
numdrives = 0

# Load the disk images into a memory mapped variable
drive0Data = msxdos_inihrd(psetvar[1][1])
drive1Data = msxdos_inihrd(psetvar[2][1])

# irc
channel = "#msxpi"

appstate = st_init
pcopystat2 = 0
pcopyindex = 0

init_spi_bitbang()
GPIO.output(rdyPin, GPIO.LOW)
print "GPIO Initialized\n"
print "Starting MSXPi Server Version ",version,"Build",build

try:
    while True:
        print("st_recvcmd: waiting command")
        rc = recvdatablock(NoTimeOutCheck)
        print("Received command",rc)

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
