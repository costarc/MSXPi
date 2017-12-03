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

struct doubleRCtype {
    int rc;
    unsigned char byte;
};

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

struct doubleRCtype piexchangebyte(bool CHECKTIMEOUT, unsigned char pibyte) {
    struct doubleRCtype ret;
    time_t t = time(NULL) + BYTETRANSFTIMEOUT;
    ret.rc = RC_SUCCESS;
    gpioWrite(rdy,HIGH);
    while (gpioRead(cs) == HIGH) {
        if (CHECKTIMEOUT)
            if (time(NULL) >= t) {
                ret.rc = RC_TIMEOUT;
                break;
            }
    }
    
    if (ret.rc == RC_SUCCESS)
        ret.byte = SPI_MASTER_transfer_byte(pibyte);
    
    gpioWrite(rdy,LOW);
    return ret;
}

int uploaddata(char *data, size_t totalsize, int index, int GLOBALRETRIES) {
    int rc,crc,bytecounter,myblocksize,msxblocksize;
    unsigned char pibyte;
    struct doubleRCtype msxdata;
    int msb,lsb;
    
    msxdata = piexchangebyte(true,STARTTRANSFER);
    if (msxdata.byte != STARTTRANSFER) {
        printf("uploaddata.c: Out of sync - received:%x\n",msxdata.byte);
        return RC_OUTOFSYNC;
    }
    
    // read blocksize, MAXIMUM 65535 KB
    msxdata = piexchangebyte(true,SENDNEXT);
    lsb = msxdata.byte;
    msxdata = piexchangebyte(true,SENDNEXT);
    msb = msxdata.byte;
    msxblocksize = lsb+256*msb;
    myblocksize = msxblocksize;
           
    //Now verify if has finished transfering data
    if (index*msxblocksize >= totalsize) {
        piexchangebyte(true,ENDTRANSFER);
        return ENDTRANSFER;
    }
    
    piexchangebyte(true,SENDNEXT);
    
    //printf("uploaddata.c:recv:%i ",msxblocksize);
    // send back to msx the block size, or the actual file size if blocksize > totalsize
    if (totalsize <= index*msxblocksize+msxblocksize)
        myblocksize = totalsize - (index*msxblocksize);
    
    
    //printf("uploaddata.c: Starting at position: %i\n",index*myblocksize);
    
    piexchangebyte(true,myblocksize % 256); piexchangebyte(true,myblocksize / 256);
    crc = 0;
    bytecounter = 0;
    while(bytecounter<myblocksize) {
        pibyte = *(data + (index*myblocksize) + bytecounter);
        piexchangebyte(true,pibyte);
        crc ^= pibyte;
        bytecounter++;
    }
    
    // exchange crc
    msxdata = piexchangebyte(true,crc);
    if (msxdata.byte == crc)
        rc = RC_SUCCESS;
    else
        rc = RC_CRCERROR;
    
    //printf("uploaddata.c:exiting rc = %x\n",rc);
    return rc;
}

int main(int argc, char *argv[]){
    FILE *file;
    char *buffer;
    char *p;
    size_t fileLen;
    int GLOBALRETRIES, pcopyindex,rc;
    
    //printf("upploaddata.c: Starting\n");
    
    if (argc != 5){
        printf("wrong number of arguments\n");
        return 1;
    }
    
    if (gpioInitialise() < 0){
        printf("pigpio initialisation failed\n");
        return 1;
    }
    
    errno = 0;
    size_t conv = strtol(argv[2], &p, 10);
    if (errno != 0 || *p != '\0' || conv > INT_MAX) {
        printf("fileLen parameter invalid or not numeric\n");
        return 1;
    } else
        fileLen = conv;

    errno = 0;
    conv = strtol(argv[3], &p, 10);
    if (errno != 0 || *p != '\0' || conv > INT_MAX) {
        printf("pcopyindex parameter invalid or not numeric\n");
        return 1;
    } else
        pcopyindex = conv;
    
    errno = 0;
    int convi = strtol(argv[4], &p, 10);
    if (errno != 0 || *p != '\0' || convi > INT_MAX) {
        printf("GLOBALRETRIES parameter invalid or not numeric\n");
        return 1;
    } else
        GLOBALRETRIES = convi;
    
    //open file and read to buffer
    file = fopen(argv[1], "rb");
    if (!file)
    {
        printf("Unable to open file %s", argv[1]);
        return 1;
    }

    //Get file length
    //fseek(file, 0L, SEEK_END);
    //fileLen=ftell(file);
    //rewind(file);
    
    //Allocate memory
    buffer = malloc(sizeof(unsigned char) * fileLen);
    
    if (!buffer)
    {
        printf("Memory allocation error!");
        fclose(file);
        gpioTerminate();
        return 1;
    }
    
    fread(buffer,fileLen,1,file);
    fclose(file);
    init_spi_bitbang();
    gpioWrite(rdy,LOW);
    rc = uploaddata(buffer,fileLen,pcopyindex,GLOBALRETRIES);
    free(buffer);
    gpioWrite(rdy,LOW);
    gpioTerminate();
    //printf("upploaddata.c: Exiting with rc = %x\n",rc);
    return rc;
}
