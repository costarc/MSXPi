/*
 ;|===========================================================================|
 ;|                                                                           |
 ;| MSXPi Interface                                                           |
 ;|                                                                           |
 ;| Version : 0.8.1                                                           |
 ;|                                                                           |
 ;| Copyright (c) 2015-2016 Ronivon Candido Costa (ronivon@outlook.com)       |
 ;|                                                                           |
 ;| All rights reserved                                                       |
 ;|                                                                           |
 ;| Redistribution and use in source and compiled forms, with or without      |
 ;| modification, are permitted under GPL license.                            |
 ;|                                                                           |
 ;|===========================================================================|
 ;|                                                                           |
 ;| This file is part of MSXPi Interface project.                             |
 ;|                                                                           |
 ;| MSX PI Interface is free software: you can redistribute it and/or modify  |
 ;| it under the terms of the GNU General Public License as published by      |
 ;| the Free Software Foundation, either version 3 of the License, or         |
 ;| (at your option) any later version.                                       |
 ;|                                                                           |
 ;| MSX PI Interface is distributed in the hope that it will be useful,       |
 ;| but WITHOUT ANY WARRANTY; without even the implied warranty of            |
 ;| MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the             |
 ;| GNU General Public License for more details.                              |
 ;|                                                                           |
 ;| You should have received a copy of the GNU General Public License         |
 ;| along with MSX PI Interface.  If not, see <http://www.gnu.org/licenses/>. |
 ;|===========================================================================|
 ;
 ; File history :
 ; 0.1 2017/11/18
 */

#include <stdio.h>
#include <pigpio.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <sys/stat.h>
#include <curl/curl.h>
#include <assert.h>
#include <time.h>
#include <unistd.h>
#include <stdbool.h>
#include <sys/mman.h>
#include <fcntl.h>
#include <errno.h>   // for errno
#include <limits.h>  // for INT_MAX

#define TZ (0)
#define version "0.8.1"
#define build "20171106.00087"

//#define V07SUPPORT
#define DISKIMGPATH "/home/pi/msxpi/disks"
#define HOMEPATH "/home/pi/msxpi"

/* GPIO pin numbers used in this program */

#define cs    21
#define sclk  20
#define mosi  16
#define miso  12
#define rdy   25

#define SPI_SCLK_LOW_TIME 0
#define SPI_SCLK_HIGH_TIME 0
#define HIGH 1
#define LOW 0
#define command 1
#define binary  2

#define SPI_INT_TIME            3000
#define PIWAITTIMEOUTOTHER      120      // seconds
#define PIWAITTIMEOUTBIOS       60      // seconds
#define SYNCTIMEOUT             5
#define BYTETRANSFTIMEOUT       5
#define SYNCTRANSFTIMEOUT       3

#define RC_SUCCESS              0xE0
#define RC_INVALIDCOMMAND       0xE1
#define RC_CRCERROR             0xE2
#define RC_TIMEOUT              0xE3
#define RC_INVALIDDATASIZE      0xE4
#define RC_OUTOFSYNC            0xE5
#define RC_FILENOTFOUND         0xE6
#define RC_FAILED               0xE7
#define RC_INFORESPONSE         0xE8
#define RC_WAIT                 0xE9
#define RC_READY                0xEA
#define RC_SUCCNOSTD            0XEB
#define RC_FAILNOSTD            0XEC
#define RC_UNDEFINED            0xEF

#define st_init                 0       // waiting loop, waiting for a command
#define st_cmd                  1       // transfering data for a command
#define st_recvdata             2
#define st_senddata             4
#define st_synch                5       // running a command received from MSX
#define st_runcmd               6
#define st_shutdown             99

// commands
#define CMDREAD         0x00
#define LOADROM         0x01
#define LOADCLIENT      0x02

// from 0x03 to 0xF reserver
// 0xAA - 0xAF : Control code
#define STARTTRANSFER   0xA0
#define SENDNEXT        0xA1
#define ENDTRANSFER     0xA2
#define READY           0xAA
#define ABORT           0xAD
#define WAIT            0xAE

#define WIFICFG         0x1A
#define CMDDIR          0x1D
#define CMDPIFSM        0x33
#define CMDGETSTAT      0x55
#define SHUTDOWN        0x66
#define DATATRANSF      0x77
#define CMDSETPARM      0x7A
#define CMDSETPATH      0x7B
#define CMDPWD          0x7C
#define CMDMORE         0x7D
#define CMDPATHERR1     0x7E
#define UNKERR          0x98
#define FNOTFOUND       0x99
#define PI_READY        0xAA
#define NOT_READY       0xAF
#define RUNPICMD        0xCC
#define CMDSETVAR       0xD1
#define NXTDEV_INFO     0xE0
#define NXTDEV_STATUS   0xE1
#define NXTDEV_RSECT    0xE2
#define NXTDEV_WSECT    0xE3
#define NXTLUN_INFO     0xE4
#define CMDERROR        0xEE
#define FNOTFOUD        0xEF
#define CMDLDFILE       0xF1
#define CMDSVFILE       0xF5
#define CMDRESET        0xFF
#define RAW     0
#define LDR     1
#define CLT     2
#define BIN     3
#define ROM     4
#define FSLOCAL     1
#define FSUSB1      2
#define FSUSB2      3
#define FSNFS       4
#define FSWIN       5
#define FSHTTP      6
#define FSHTTPS     7
#define FSFTP       8
#define FSFTPS      9

// MSX-DOS2 Error Codes
#define __NOFIL     0xD7
#define __DISK      0xFD
#define __SUCCESS   0x00

typedef struct {
    unsigned char rc;
    int  datasize;
} transferStruct;

typedef struct {
    unsigned char deviceNumber;
    unsigned char mediaDescriptor;
    unsigned char logicUnitNumber;
    unsigned char sectors;
    int           initialSector;
} DOS_SectorStruct;

struct DiskImgInfo {
    int rc;
    char dskname[65];
    unsigned char *data;
    unsigned char deviceNumber;
    double size;
};

struct psettype {
    char var[16];
    char value[254];
};

struct curlMemStruct {
    unsigned char *memory;
    size_t size;
};
typedef struct curlMemStruct MemoryStruct;

unsigned char appstate = st_init;
unsigned char msxbyte;
unsigned char msxbyterdy;
unsigned char pibyte;
int debug;
bool CHECKTIMEOUT = false;
bool PIEXCHANGETIMEDOUT = false;

void init_spi_bitbang(void) {
    gpioSetMode(cs, PI_INPUT);
    gpioSetMode(sclk, PI_OUTPUT);
    gpioSetMode(mosi, PI_INPUT);
    gpioSetMode(miso, PI_OUTPUT);
    gpioSetMode(rdy, PI_OUTPUT);
    
    gpioSetPullUpDown(cs, PI_PUD_UP);
    gpioSetPullUpDown(mosi, PI_PUD_DOWN);
    
}

void write_MISO(unsigned char bit) {
    gpioWrite(miso, bit);
}

void tick_sclk(void) {
    gpioWrite(sclk,HIGH);
    gpioDelay(SPI_SCLK_HIGH_TIME);
    gpioWrite(sclk,LOW);
    gpioDelay(SPI_SCLK_LOW_TIME);
}

// This is where the SPI protocol is implemented.
// This function will transfer a byte (send and receive) to the MSX Interface.
// It receives a byte as input, return a byte as output.
// It is full-duplex, sends a bit, read a bit in each of the 8 cycles in the loop.
// It is tightely linked to the register-shift implementation in the CPLD,
// If something changes there, it must have changes here so the protocol will match.

unsigned char SPI_MASTER_transfer_byte(unsigned char byte_out) {
    unsigned char byte_in = 0;
    unsigned char bit;
    unsigned rdbit;
    
    tick_sclk();
    
    for (bit = 0x80; bit; bit >>= 1) {
        
        write_MISO((byte_out & bit) ? HIGH : LOW);
        gpioWrite(sclk,HIGH);
        gpioDelay(SPI_SCLK_HIGH_TIME);
        
        rdbit = gpioRead(mosi);
        if (rdbit == HIGH)
            byte_in |= bit;
        
        gpioWrite(sclk,LOW);
        gpioDelay(SPI_SCLK_LOW_TIME);
        
    }
    
    tick_sclk();
    return byte_in;
    
}

int piexchangebyte(unsigned char mypibyte) {
    time_t t = time(NULL) + BYTETRANSFTIMEOUT;
    int mymsxbyte;
    gpioWrite(rdy,HIGH);
    PIEXCHANGETIMEDOUT = false;
    while (gpioRead(cs) == HIGH) {
        if (CHECKTIMEOUT)
            if (time(NULL) >= t) {
                PIEXCHANGETIMEDOUT = true;
                break;
            }
    }
    
    mymsxbyte = SPI_MASTER_transfer_byte(mypibyte);
    gpioWrite(rdy,LOW);
    return mymsxbyte;
}

/* senddatablock
 ---------------
 21/03/2017
 
 Send a block of data to MSX. Read the data from a pointer passed to the function.
 Do not retry if it fails (this should be implemented somewhere else).
 Will inform the block size to MSX (two bytes) so it knows the size of transfer.
 
 Logic sequence is:
 1. read MSX status (expect SENDNEXT)
 2. send lsb for block size
 3. send msb for block size
 4. read (lsb+256*msb) bytes from buffer and send to MSX
 5. exchange crc with msx
 6. end function and return status
 
 Return code will contain the result of the oepration.
 */
transferStruct senddatablock(unsigned char *buffer, int datasize, bool sendsize) {
    
    transferStruct dataInfo;
    
    int bytecounter = 0;
    unsigned char mymsxbyte,mypibyte;
    unsigned char crc = 0;
    
    //printf("senddatablock: starting\n");
    mymsxbyte = piexchangebyte(SENDNEXT);
    
    if (mymsxbyte != SENDNEXT) {
        printf("senddatablock:Out of sync with MSX, waiting SENDNEXT, received %x\n",mymsxbyte);
        dataInfo.rc = RC_OUTOFSYNC;
    } else {
        // send block size if requested by caller.
        if (sendsize)
            piexchangebyte(datasize % 256); piexchangebyte(datasize / 256);
        
        //printf("senddatablock:blocksize = %i\n",datasize);
        
        while(datasize>bytecounter && mymsxbyte>=0) {
            //printf("senddatablock:waiting MSX request byte\n");
            
            mypibyte = *(buffer + bytecounter);
            
            mymsxbyte = piexchangebyte(mypibyte);
            
            if (PIEXCHANGETIMEDOUT) {
                printf("senddatablock:time out error during transfer\n");
                mymsxbyte = -1;
                break;
            }
            
            if (mymsxbyte>=0) {
                //printf("senddatablock:%i Sent %x %c Received:%x\n",bytecounter,mypibyte,mypibyte,mymsxbyte);
                crc ^= mypibyte;
                bytecounter++;
            } else {
                printf("senddatablock:Error during transfer\n");
                break;
            }
        }
        
        if(mymsxbyte>=0) {
            //printf("senddatablock:Sending CRC: %x\n",crc);
            
            mymsxbyte = piexchangebyte(crc);
            
            //printf("senddatablock:Received MSX CRC: %x\n",mymsxbyte);
            if (mymsxbyte == crc) {
                //printf("mymsxbyte:CRC verified\n");
                dataInfo.rc = RC_SUCCESS;
            } else {
                dataInfo.rc = RC_CRCERROR;
                printf("senddatablock:CRC ERROR CRC: %x different than MSX CRC: %x\n",crc,dataInfo.rc);
            }
            
        } else {
            dataInfo.rc = RC_TIMEOUT;
        }
    }
    
    //printf("senddatablock:exiting with rc = %x\n",dataInfo.rc);
    return dataInfo;
}

/* recvdatablock
 ---------------
 Read a block of data from MSX and stores in the pointer passed to the function.
 Do not retry if it fails (this should be implemented somewhere else).
 Will read the block size from MSX (two bytes) to know size of transfer.
 
 Logic sequence is:
 1. read MSX status (expect SENDNEXT)
 2. read lsb for block size
 3. read msb for block size
 4. read (lsb+256*msb) bytes from MSX and store in buffer
 5. exchange crc with msx
 6. end function and return status
 
 Return code will contain the result of the oepration.
 */

transferStruct recvdatablock(unsigned char *buffer) {
    transferStruct dataInfo;
    
    int bytecounter = 0;
    unsigned char mymsxbyte;
    unsigned char crc = 0;
    
    //printf("recvdatablock:starting\n");
    mymsxbyte = piexchangebyte(SENDNEXT);
    if (mymsxbyte != SENDNEXT) {
        printf("recvdatablock:Out of sync with MSX, waiting SENDNEXT, received %x\n",mymsxbyte);
        dataInfo.rc = RC_OUTOFSYNC;
    } else {
        // read block size
        dataInfo.datasize = (unsigned char)piexchangebyte(SENDNEXT)+(256 * (unsigned char)piexchangebyte(SENDNEXT));
        //printf("recvdatablock:blocksize = %i\n",dataInfo.datasize);
        
        while(dataInfo.datasize>bytecounter && mymsxbyte>=0) {
            //printf("recvdatablock:waiting byte from MSX\n");
            
            mymsxbyte = piexchangebyte(SENDNEXT);
            
            if (mymsxbyte>=0) {
                //printf("recvdatablock:Received byte:%x\n",mymsxbyte);
                *(buffer + bytecounter) = mymsxbyte;
                crc ^= mymsxbyte;
                bytecounter++;
            } else {
                //printf("recvdatablock:Error during transfer\n");
                break;
            }
        }
        
        if(mymsxbyte>=0) {
            //printf("recvdatablock:Sending CRC: %x\n",crc);
            
            mymsxbyte = piexchangebyte(crc);
            
            //printf("recvdatablock:Received MSX CRC: %x\n",mymsxbyte);
            if (mymsxbyte == crc) {
                //printf("recvdatablock:CRC verified\n");
                dataInfo.rc = RC_SUCCESS;
            } else {
                dataInfo.rc = RC_CRCERROR;
                //printf("recvdatablock:CRC ERROR CRC: %x different than MSX CRC: %x\n",crc,dataInfo.rc);
            }
            
        } else {
            dataInfo.rc = RC_TIMEOUT;
        }
    }
    
    //printf("recvdatablock:exiting with rc = %x\n",dataInfo.rc);
    return dataInfo;
}

int secsenddata(unsigned char *buf, int filesize,int GLOBALRETRIES) {
    
    int rc;
    int blockindex,numsectors,initsector,mymsxbyte,blocksize,retries;
    transferStruct dataInfo;
    
    mymsxbyte = piexchangebyte(SENDNEXT);
    //printf("secsenddata:Sent SENDNEXT, received:%x\n",mymsxbyte);
    
    if(mymsxbyte!=SENDNEXT) {
        rc = RC_OUTOFSYNC;
        printf("secsenddata:Exiting with rc:%x\n",rc);
        return rc;
    }
    
    piexchangebyte(filesize % 256); piexchangebyte(filesize / 256);
    //printf("secsenddata:Sent filesize: %i\n",filesize);
    
    
    // now send 512 bytes at a time.
    blockindex = 0;
    if (filesize>512) blocksize = 512; else blocksize = filesize;
    while(blockindex<filesize) {
        retries=0;
        rc = RC_UNDEFINED;
        while(retries<GLOBALRETRIES && rc != RC_SUCCESS) {
            rc = RC_UNDEFINED;
            //printf("secsenddata:inner:index = %i retries:%i filesize:%i  blocksize:%i\n",blockindex,retries,filesize,blocksize);
            dataInfo = senddatablock(buf+blockindex,blocksize,true);
            rc = dataInfo.rc;
            retries++;
        }
        
        // Transfer interrupted due to CRC error
        if(retries>=GLOBALRETRIES) break;
        
        blockindex += 512;
        //blockindex += blocksize;
        
        if (filesize-blockindex>512) blocksize = 512; else blocksize = filesize-blockindex;
        //printf("secsenddata:outer:index = %i retries:%i filesize:%i  blocksize:%i  rc:%x\n",blockindex,retries,filesize,blocksize,rc);
        
    }
    
    //printf("secsenddata:Exiting transfer loop with rc:%x\n",rc);
    
    if(retries>=GLOBALRETRIES) {
        printf("secsenddata:Transfer interrupted due to CRC error\n");
        rc = RC_CRCERROR;
    } else {
        rc = dataInfo.rc;
    }
    
    //printf("secsenddata:Exiting with rc:%x\n",rc);
    return rc;
    
}

int main(int argc, char *argv[]){
    FILE *file;
    char *buffer;
    unsigned long fileLen;
    int GLOBALRETRIES;
    char *p;
    int rc = 0;
    transferStruct dataInfo;
    
    printf("GPIO Initialized\n");
    printf("Starting MSXPi Server Python module Version %s Build %s\n",version,build);
    
    if (argc != 3){
        fprintf(stderr, "wrong number of arguments\n");
        return 0;
    }
    
    if (gpioInitialise() < 0){
        fprintf(stderr, "pigpio initialisation failed\n");
        return 0;
    }
    
    init_spi_bitbang();
    gpioWrite(rdy,LOW);
    
    // get GLBOARETRIES from argv
    errno = 0;
    long conv = strtol(argv[2], &p, 10);
    if (errno != 0 || *p != '\0' || conv > INT_MAX) {
        fprintf(stderr, "GLOBALRETRIES parameters invalid or non numeric\n");
        return 0;
    } else
        GLOBALRETRIES = conv;
    
    // open file and read to buffer
    file = fopen(argv[1], "rb");
    if (!file)
    {
        fprintf(stderr, "Unable to open file %s", argv[1]);
        gpioTerminate();
        return 0;
    }
    
    //Get file length
    fseek(file, 0, SEEK_END);
    fileLen=ftell(file);
    fseek(file, 0, SEEK_SET);
    
    //Allocate memory
    buffer=(char *)malloc(fileLen+1);
    if (!buffer)
    {
        fprintf(stderr, "Memory error!");
        fclose(file);
        gpioTerminate();
        return 0;
    }
    
    //Read file contents into buffer
    fread(buffer, fileLen, 1, file);
    fclose(file);
    
    bool loop = true;
    int pcopyindex = 0;
    int retries = 0;
    
    while (loop) {
        dataInfo = senddatablock(&buffer,fileLen,true);

        if (rc==ENDTRANSFER) {
            printf("ENDTRANSFER\n");
            free(buffer);
            rc = RC_SUCCESS;
            loop = false;
        } else if (rc==RC_SUCCESS) {
            printf("loop:index = %i\n",pcopyindex);
            pcopyindex++;
        } else if (rc==RC_CRCERROR && retries < GLOBALRETRIES) {
            printf("loop:crcerror - retry = %i\n",retries);
            retries++;
        } else {
            printf("!!!!! Error !!!!!\n");
            free(buffer);
            rc = RC_FAILED;
            loop = false;
        
        }
    }
    
    printf("Terminating GPIO\n");
    gpioWrite(rdy,LOW);
    gpioTerminate();
        
    return 0;
}
