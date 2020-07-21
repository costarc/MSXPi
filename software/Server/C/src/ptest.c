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
 ; Compile with:
 ; gcc -Wall -pthread -o ptest ptest.c -lpigpio -lrt
 */

#include <pigpio.h>
#include <stdlib.h>
#include <errno.h>   // for errno
#include <limits.h>  // for INT_MAX
#include <time.h>
#include <stdbool.h>
#include <stdio.h>

#define TZ (0)
#define version "0.8.1"
#define build "20200717.00000"

#define HOMEPATH "/home/pi/msxpi"

/* GPIO pin numbers used in this program */

#define csPin    21
#define sclkPin  20
#define mosiPin  16
#define misoPin  12
#define rdyPin   25

#define SPI_SCLK_LOW_TIME 0.0001
#define SPI_SCLK_HIGH_TIME 0.0001
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
    gpioSetMode(csPin, PI_INPUT);
    gpioSetMode(sclkPin, PI_OUTPUT);
    gpioSetMode(mosiPin, PI_INPUT);
    gpioSetMode(misoPin, PI_OUTPUT);
    gpioSetMode(rdyPin, PI_OUTPUT);
    gpioSetPullUpDown(csPin, PI_PUD_UP);
    gpioSetPullUpDown(mosiPin, PI_PUD_UP);
}

void write_MISO(unsigned char bit) {
    gpioWrite(misoPin, bit);
}

void tick_sclk(void) {
    gpioWrite(sclkPin,HIGH);
    //gpioDelay(SPI_SCLK_HIGH_TIME);
    gpioWrite(sclkPin,LOW);
    //gpioDelay(SPI_SCLK_LOW_TIME);
}

// This is where the SPI protocol is implemented.
// This function will transfer a byte (send and receive) to the MSX Interface.
// It receives a byte as input, return a byte as output.
// It is full-duplex, sends a bit, read a bit in each of the 8 cycles in the loop.
// It is tightely linked to the register-shift implementation in the CPLD,
// If something changes there, it must have changes here so the protocol will match.

void send_byte(unsigned char byte_out) {
    unsigned char bit;

    gpioWrite(misoPin,HIGH);
    while (gpioRead(csPin) == HIGH) 
        { }

    gpioWrite(misoPin,LOW);
    tick_sclk();
    for (bit = 0x80; bit; bit >>= 1) {
        write_MISO((byte_out & bit) ? HIGH : LOW);
        gpioWrite(sclkPin,HIGH);
        //gpioDelay(SPI_SCLK_HIGH_TIME);
        gpioWrite(sclkPin,LOW);
        //gpioDelay(SPI_SCLK_LOW_TIME);
    }
    gpioWrite(rdyPin,LOW);
    //gpioDelay(SPI_SCLK_LOW_TIME);
    gpioWrite(rdyPin,HIGH);
    gpioWrite(misoPin,HIGH);


}

unsigned char receive_byte() {
    unsigned char bit;
    unsigned char byte_in = 0;
    unsigned rdbit;

    gpioWrite(misoPin,HIGH);
    while (gpioRead(csPin) == HIGH) 
        { }

    gpioWrite(misoPin,LOW);

    tick_sclk();
    for (bit = 0x80; bit; bit >>= 1) {
        gpioWrite(sclkPin,HIGH);
        //gpioDelay(SPI_SCLK_HIGH_TIME);
        rdbit = gpioRead(mosiPin);
        if (rdbit == HIGH)
            byte_in |= bit;

        gpioWrite(sclkPin,LOW);
        //gpioDelay(SPI_SCLK_LOW_TIME);
    }

    gpioWrite(rdyPin,LOW);
    //gpioDelay(SPI_SCLK_LOW_TIME);
    gpioWrite(rdyPin,HIGH);
    gpioWrite(misoPin,HIGH);
    return byte_in;

}

int main(int argc, char *argv[]){
    
    int dsL,dsM,m,errors,i = 0;

    fprintf(stderr,"Starting ptest\n");

    fprintf(stderr, "gpioInitialise\n");    
    if (gpioInitialise() < 0){
        fprintf(stderr, "pigpio initialisation failed\n");
    }

    init_spi_bitbang();
    gpioWrite(rdyPin,LOW);
    gpioWrite(rdyPin,HIGH);
    gpioWrite(misoPin,LOW);

    send_byte(RC_SUCCESS);
    for (i = 0; i < 10; i +=1)
        receive_byte(RC_SUCCESS);

    for (i = 0; i<65536; i +=1) {
        dsL = receive_byte();
        dsM = receive_byte();
        m = (dsL + (256 * dsM));
        if (i != m) 
            errors += 1;
        
        fprintf(stderr, "%d %d\n",i,m);

    }

    fprintf(stderr,"Receiving errors:%d\n",errors);

    fprintf(stderr,"ptest:starting transmission test\n");
    for (i = 0; i<65536; i += 1) {
        send_byte((i) % 256);
        send_byte((i) / 256);
    }

    fprintf(stderr, "ptest.c: Exiting\n");

    return 0;

}
