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
#include <errno.h>   // for errno
#include <limits.h>  // for INT_MAX
#include <time.h>
#include <stdbool.h>

#define TZ (0)
#define version "0.8.1"
#define build "20171106.00087"

#define GLOBALRETRIES 5

#define HOMEPATH "/home/pi/msxpi"

/* GPIO pin numbers used in this program */

bool PIEXCHANGETIMEDOUT = false;
bool CHECKTIMEOUT = false;

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

struct doubleRCtype {
    int rc;
    unsigned char byte;
};

typedef struct {
    unsigned char rc;
    int  datasize;
} transferStruct;

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

int loadbin(char *file) {
    int rc;
    FILE *fp;
    int filesize,index,blocksize,retries;
    unsigned char *buf;
    char *stdout;
    unsigned char mymsxbyte;
    char** tokens;
    transferStruct dataInfo;
    
    //printf("loadbin:starting %s\n",msxcommand);
    
    //printf("ploadbin.msx:file name is <%s>\n\n",file);
    
    rc = RC_UNDEFINED;
    
    fp = fopen(file,"rb");
    if (fp) {
        fseek(fp, 0L, SEEK_END);
        filesize = ftell(fp);
        rewind(fp);
        buf = malloc(sizeof(*buf) * filesize);
        fread(buf,filesize,1,fp);
        fclose(fp);
        
        index = 0;
        
        if (*(buf)!=0xFE) {
            printf("ploadbin.msx:Not a .bin program. Aborting\n");
            rc = RC_UNDEFINED;
            stdout = malloc(sizeof(*stdout) * 19);
            strcpy(stdout,"Pi:Not a .bin file");
            piexchangebyte(ABORT);
        } else {
            
            piexchangebyte(STARTTRANSFER);
            
            // send to msx the total size of file
            //printf("ploadbin.msx:sending file size %i\n",filesize - 7);
            piexchangebyte((filesize - 7) % 256); piexchangebyte((filesize - 7) / 256);
            
            // send file header: 0xFE
            piexchangebyte(*(buf+index));index++;
            // program start address
            piexchangebyte(*(buf+index));index++;
            piexchangebyte(*(buf+index));index++;
            
            // program end address
            piexchangebyte(*(buf+index));index++;
            piexchangebyte(*(buf+index));index++;
            
            // program exec address
            piexchangebyte(*(buf+index));index++;
            piexchangebyte(*(buf+index));index++;
            
            //printf("ploadbin.msx:Start address = %02x%02x Exec address = %02x%02x\n",*(buf+2),*(buf+1),*(buf+4),*(buf+3));
            
            //printf("ploadbin.msx:calling senddatablock\n");
            
            // now send 512 bytes at a time.
            
            if (filesize>512) blocksize = 512; else blocksize = filesize;
            while(blocksize) {
                retries=0;
                dataInfo.rc = RC_UNDEFINED;
                while(retries<GLOBALRETRIES && dataInfo.rc != RC_SUCCESS) {
                    dataInfo.rc = RC_UNDEFINED;
                    dataInfo = senddatablock(buf+index,blocksize,true);
                    //printf("ploadbin.msx:index = %i blocksize = %i retries:%i rc:%x\n",index,blocksize,retries,dataInfo.rc);
                    retries++;
                    rc = dataInfo.rc;
                }
                
                // Transfer interrupted due to CRC error
                if(retries>GLOBALRETRIES) break;
                
                index += blocksize;
                if (filesize - index > 512) blocksize = 512; else blocksize = filesize - index;
            }
            
            //printf("loploadbin.msx:(exited) index = %i blocksize = %i retries:%i rc:%x\n",index,blocksize,retries,dataInfo.rc);
            mymsxbyte = piexchangebyte(ENDTRANSFER);
            
            if(retries>=GLOBALRETRIES || rc != RC_SUCCESS) {
                printf("ploadbin.msx:Error during data transfer:%x\n",rc);
                rc = RC_CRCERROR;
                stdout = malloc(sizeof(*stdout) * 13);
                
                strcpy(stdout,"Pi:CRC Error");
            } else {
                //printf("ploadbin.msx:done\n");
                stdout = malloc(sizeof(*stdout) * 15);
                strcpy(stdout,"Pi:File loaded");
            }
            
            mymsxbyte = piexchangebyte(ENDTRANSFER);
            
        }
        
        free(buf);
        
    } else {
        printf("ploadbin.msx:error opening file\n");
        rc = RC_FILENOTFOUND;
        mymsxbyte = piexchangebyte(ABORT);
        stdout = malloc(sizeof(*stdout) * 22);
        strcpy(stdout,"Pi:Error opening file");
    }
    
    // if (rc!=RC_SUCCESS) {
    //printf("ploadbin:sending stdout: size=%i, %s\n",strlen(stdout)+1,stdout);
    dataInfo = senddatablock(stdout,strlen(stdout)+1,true);
    //}
    
    free(stdout);
    
    printf("ploadbin.msx:exiting rc = %x\n",rc);
    return rc;
    
}

int main(int argc, char *argv[]){
    FILE *file;
    char *buffer;
    unsigned long fileLen;
    int rc;
    
    if (argc != 2){
        fprintf(stderr, "wrong number of arguments\n");
        return 0;
    }
    
    if (gpioInitialise() < 0){
        fprintf(stderr, "pigpio initialisation failed\n");
        return 0;
    }
    
    printf("loadbin:main file name is = %s\n",argv[1]);
    
    // Send the buffer to MSX
    init_spi_bitbang();
    gpioWrite(rdy,LOW);
    rc = loadbin(argv[1]);
    gpioWrite(rdy,LOW);
    gpioTerminate();
    //printf("ploadbin: Exiting with rc = %x\n",rc);
    return rc;
}
