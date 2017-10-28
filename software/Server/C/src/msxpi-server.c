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
 ; 0.8.1  : MSX-DOS working properly.
 ; 0.8    : Rewritten with new protocol-v2
 ;          New functions, new main loop, new framework for better reuse
 ;          This version now includes MSX-DOS 1.03 driver
 ; 0.7    : Commands CD and MORE working for http, ftp, nfs, win, local files.
 ; 0.6d   : Added http suport to LOAD and FILES commands
 ; 0.6c   : Initial version commited to git
 ;
 
 PI pinout x GPIO:
 http://abyz.co.uk/rpi/pigpio/index.html
 
 
 Library required by this program and how to install:
 http://abyz.co.uk/rpi/pigpio/download.html
 
 Steps:
 sudo apt-get install libcurl4-nss-dev
 wget abyz.co.uk/rpi/pigpio/pigpio.tar
 tar xf pigpio.tar
 cd PIGPIO
 make -j4
 sudo make install
 
 To compile and run this program:
 cc -Wall -pthread -o msxpi-server msxpi-server.c -lpigpio -lrt -lcurl
 
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

#define TZ (0)
#define version "0.8.1"
#define build "20171022.00086"

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

#define GLOBALRETRIES      5

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

//Tools for waiting for a new command
pthread_mutex_t newComMutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t newComCond  = PTHREAD_COND_INITIALIZER;

void delay(unsigned int secs) {
    unsigned int retTime = time(0) + secs;   // Get finishing time.
    while (time(0) < retTime);               // Loop until it arrives.
}

char *replace(char *s,unsigned char c, unsigned char n) {
    int i;
    for(i=0;i<strlen(s);i++)
        if(s[i]==c)
            s[i] = n;
    
    return s;
}

char** str_split(char* a_str, const char a_delim) {
    char** result    = 0;
    size_t count     = 0;
    char* tmp        = a_str;
    char* last_comma = 0;
    char delim[2];
    delim[0] = a_delim;
    delim[1] = 0;
    
    /* Count how many elements will be extracted. */
    while (*tmp)
    {
        if (a_delim == *tmp)
        {
            count++;
            last_comma = tmp;
        }
        tmp++;
    }
    
    // fix for bug when delimiter is "/"
    if (a_delim==0x2f)
        count--;
    
    /* Add space for trailing token. */
    count += last_comma < (a_str + strlen(a_str) - 1);
    
    /* Add space for terminating null string so caller
     knows where the list of returned strings ends. */
    count++;
    
    result = malloc(sizeof(*result) * count);
    
    if (result)
    {
        size_t idx  = 0;
        char* token = strtok(a_str, delim);
        
        while (token)
        {
            assert(idx < count);
            *(result + idx++) = strdup(token);
            token = strtok(0, delim);
            //printf("token,idx,count = %s,%i,%i\n",token,idx,count);
        }
        
        //assert(idx == count - 1);
        *(result + idx) = 0;
    }
    
    return result;
}

char *strdup (const char *s) {
    char *d;
    d = malloc(255*sizeof(*d));          // Space for length plus nul
    if (d == NULL) return NULL;          // No memory
    strcpy (d,s);                        // Copy the characters
    return d;                            // Return the new string
}

int isDirectory(const char *path) {
    struct stat statbuf;
    if (stat(path, &statbuf) != 0)
        return 0;
    return S_ISDIR(statbuf.st_mode);
}

static void *realloc_or_free(void *ptr, size_t size) {
    void *tmp = realloc(ptr, size);
    if (tmp == NULL) {
        free(ptr);
    }
    return tmp;
}

static int get_dirent_dir(char const *path, struct dirent **result,
                          size_t *size) {
    DIR *dir = opendir(path);
    if (dir == NULL) {
        closedir(dir);
        return -1;
    }
    
    struct dirent *array = NULL;
    size_t i = 0;
    size_t used = 0;
    struct dirent *dirent;
    while ((dirent = readdir(dir)) != NULL) {
        if (used == i) {
            i += 42; // why not?
            array = realloc_or_free(array, sizeof *array * i);
            if (array == NULL) {
                closedir(dir);
                return -1;
            }
        }
        
        array[used++] = *dirent;
    }
    
    struct dirent *tmp = realloc(array, sizeof *array * used);
    if (tmp != NULL) {
        array = tmp;
    }
    
    *result = array;
    *size = used;
    
    closedir(dir);
    
    return 0;
}

static int cmp_dirent_aux(struct dirent const *a, struct dirent const *b) {
    return strcmp(a->d_name, b->d_name);
}

static int cmp_dirent(void const *a, void const *b) {
    return cmp_dirent_aux(a, b);
}

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

int secsenddata(unsigned char *buf, int filesize) {
    
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

int secrecvdata(unsigned char *buf) {
    
    int rc;
    int blockindex,numsectors,initsector,mymsxbyte,blocksize,retries;
    transferStruct dataInfo;
    int filesize;
    unsigned char bytem,bytel;
    
    mymsxbyte = piexchangebyte(SENDNEXT);
    //printf("secrecvdata:Sent SENDNEXT, received:%x\n",mymsxbyte);
    
    // Send totalfile size to transfer
    bytel = piexchangebyte(SENDNEXT);
    bytem = piexchangebyte(SENDNEXT);
    
    filesize = bytel + (bytem * 256);
    //printf("secrecvdata:bytem:%x bytel:%x filesize:%i\n",bytem,bytel,filesize);
    
    // now read 512 bytes at a time.
    blockindex = 0;
    if (filesize>512) blocksize = 512; else blocksize = filesize;
    while(blockindex<filesize) {
        retries=0;
        rc = RC_UNDEFINED;
        while(retries<GLOBALRETRIES && rc != RC_SUCCESS) {
            rc = RC_UNDEFINED;
            dataInfo = recvdatablock(buf+blockindex);
            //printf("secrecvdata:inner:index = %i retries:%i filesize:%i  blocksize:%i\n",blockindex,retries,filesize,dataInfo.datasize);
            rc = dataInfo.rc;
            retries++;
        }
        
        // Transfer interrupted due to CRC error
        if(retries>GLOBALRETRIES) break;
        
        blockindex += 512;
        
        if (filesize-blockindex>512) blocksize = 512; else blocksize = filesize-blockindex;
        //printf("secrecvdata:outer:index = %i retries:%i filesize:%i  blocksize:%i  rc:%x\n",blockindex,retries,filesize,blocksize,rc);
        
    }
    
    //printf("secrecvdata:Exiting loop with rc %x\n",rc);
    
    if(retries>GLOBALRETRIES) {
        printf("secrecvdata:Transfer interrupted due to CRC error\n");
        rc = RC_CRCERROR;
    } else {
        rc = dataInfo.rc;
    }
    
    //printf("secrecvdata:Exiting with rc %x\n",rc);
    return rc;
    
}

int sync_transf(unsigned char mypibyte) {
    time_t start_t, end_t;
    double diff_t;
    time(&start_t);
    int rc = 0;
    msxbyterdy = 0;
    pibyte = mypibyte;
    gpioWrite(rdy,HIGH);
    pthread_mutex_lock(&newComMutex);
    while (msxbyterdy == 0 && rc==0) {
        pthread_cond_wait(&newComCond, &newComMutex);
        time(&end_t);
        diff_t = difftime(end_t, start_t);
        if (diff_t > SYNCTRANSFTIMEOUT) rc = -1;
    }
    pthread_mutex_unlock(&newComMutex);
    if (msxbyterdy==0) rc = -1; else rc = msxbyte;
    return rc;
}


int sync_client() {
    int rc = -1;
    
    printf("sync_client:Syncing\n");
    while(rc<0) {
        rc = piexchangebyte(READY);
        
#ifdef V07SUPPORT
        
        if (rc == LOADCLIENT) {
            LOADCLIENT_V07PROTOCOL();
            rc = READY;
        }
        
#endif
        
    }
    
    return rc;
}

int ptype(unsigned char *msxcommand) {
    int rc;
    FILE *fp;
    int filesize;
    unsigned char *buf;
    unsigned char *fname;
    transferStruct dataInfo;
    
    //printf("ptype:starting %s\n",msxcommand);
    
    if (strlen(msxcommand)>5) {
        fname = malloc((sizeof(*fname) * strlen(msxcommand)) - 5);
        strcpy(fname,msxcommand+6);
        
        //printf("ptype:fname is %s\n",fname);

        fp = fopen(fname,"rb");
        if(fp) {
            //printf("ptype:file name to show is %s\n",fname);
            fseek(fp, 0L, SEEK_END);
            filesize = ftell(fp);        // file has 4 zeros at the end, we only need one
            rewind(fp);
            
            buf = malloc((sizeof(*buf) * filesize) + 1);
            fread(buf,filesize,1,fp);
            fclose(fp);
            
            *(buf + filesize) = 0;
        } else {
            filesize = 22;
            buf = malloc(sizeof(*buf) * filesize);
            strcpy(buf,"Pi:Error opening file");
        }
        
        free(fname);
        
    } else {
        filesize = 22;
        buf = malloc(sizeof(*buf) * filesize);
        strcpy(buf,"Pi:Error opening file");
    }
    
    //printf("ptype:file size is %i\n",filesize);
    dataInfo = senddatablock(buf,filesize+1,true);
    free(buf);
    rc = dataInfo.rc;
    //printf("ptype:exiting rc = %x\n",rc);
    return rc;
    
}

int runpicmd(char *msxcommand) {
    int rc;
    FILE *fp;
    int filesize;
    char *buf;
    char *fname;
    
    printf("runpicmd:starting command >%s<+\n",msxcommand);
    
    piexchangebyte(RC_WAIT);
    
    fname = malloc(sizeof(*fname) * 256);
    sprintf(fname,"%s>/tmp/msxpi_out.txt 2>&1",msxcommand);
    
    //printf("runpicmd:prepared output in command >%s<\n",fname);
    
    if(fp = popen(fname, "r")) {
        fclose(fp);
        filesize = 24;
        buf = malloc(sizeof(*buf) * 256 );
        strcpy(buf,"ptype /tmp/msxpi_out.txt");
        //printf("ptype:Success running command %s\n",fname);
        rc = RC_SUCCESS;
    } else {
        printf("ptype:Error running command %s\n",fname);
        filesize = 22;
        buf = malloc(sizeof(*buf) * 256 );
        strcpy(buf,"Pi:Error running command");
        rc = RC_FILENOTFOUND;
    }
    
    //printf("runpicmd:call more to send output\n");
    if (rc==RC_SUCCESS) {
        piexchangebyte(RC_SUCCESS);
        ptype(buf);
    } else {
        piexchangebyte(RC_FAILED);
        senddatablock(buf,strlen(buf)+1,true);
    }
    
    free(buf);
    free(fname);
    
    printf("runpicmd:exiting rc = %x\n",rc);
    return rc;
    
}

int ploadrom(struct psettype *psetvar,char *msxcommand) {
    int rc, sz;
    FILE *fp;
    int filesize,index,blocksize,retries;
    unsigned char *buf;
    char *stdout;
    char *newpath;
    transferStruct dataInfo;
    char** tokens;
    
    printf("load:starting %s\n",msxcommand);
    
    if (piexchangebyte(RC_WAIT)!=SENDNEXT) {
        printf("ploadrom:out of sync\n");
        return RC_FAILED;
    }
    
    tokens = str_split(msxcommand,' ');
    printf("load:parsed command is %s %s\n",*(tokens),*(tokens + 1));

    dataInfo.rc = RC_UNDEFINED;
    
    sz = (sizeof(*newpath) * (strlen(psetvar[0].value)+strlen(*(tokens + 1)))) + 2;
    
    printf("newpath size will be: %i\n",sz);
    
    newpath = malloc(sz);
    strcpy(newpath,psetvar[0].value);
    strcat(newpath,"/");
    strcat(newpath,*(tokens + 1));
    
    printf("ploadrom:append to relative path: result is %s\n",newpath);

    stdout = malloc(sizeof(*stdout) * 65);
    
    fp = fopen(newpath,"rb");
    if (fp) {
        printf("Found file\n");
        fseek(fp, 0L, SEEK_END);
        filesize = ftell(fp);
        rewind(fp);
        buf = malloc(sizeof(*buf) * filesize + 1);
        fread(buf,filesize,1,fp);
        fclose(fp);
        
        printf("File read into buffer\n");
        
        if ((*(buf)!='A') || (*(buf+1)!='B')) {
            printf("loadrom:Not a .rom program. Aborting\n");
            rc = RC_UNDEFINED;
            strcpy(stdout,"Pi:Not a .rom file");
            piexchangebyte(RC_FAILED);
        } else {
            
            // This status tells MSX to start receiving data
            if (piexchangebyte(RC_SUCCNOSTD)!=SENDNEXT) {
                printf("ploadrom:out of sync: RC_SUCCNOSTD\n");
                return RC_FAILED;
            }
            
            
            // Now enters into the logic for MSX "LOADROM"
            if (piexchangebyte(STARTTRANSFER)!=STARTTRANSFER) {
                printf("ploadrom:out of sync: STARTTRANSFER\n");
                return RC_FAILED;
            }
            
            // send to msx the total size of file
            printf("load:sending file size %i\n",filesize);
            piexchangebyte(filesize % 256); piexchangebyte(filesize / 256);
            
            //printf("load:calling senddatablock\n");
            
            // now send 512 bytes at a time.
            index = 0;
            
            if (filesize>512) blocksize = 512; else blocksize = filesize;
            while(blocksize) {
                retries=0;
                dataInfo.rc = RC_UNDEFINED;
                while(retries<GLOBALRETRIES && dataInfo.rc != RC_SUCCESS) {
                    dataInfo.rc = RC_UNDEFINED;
                    //printf("load:index = %i %04x blocksize = %i retries:%i rc:%x\n",index,index+0x4000,blocksize,retries,dataInfo.rc);
                    dataInfo = senddatablock(buf+index,blocksize,true);
                    retries++;
                    rc = dataInfo.rc;
                }
                
                // Transfer interrupted due to CRC error
                if(retries>GLOBALRETRIES) break;
                
                index += blocksize;
                if (filesize - index > 512) blocksize = 512; else blocksize = filesize - index;
            }
            
            if(retries>=GLOBALRETRIES) {
                printf("load:Transfer interrupted due to CRC error\n");
                rc = RC_CRCERROR;
                strcpy(stdout,"Pi:CRC Error");
                piexchangebyte(ABORT);
            } else {
                printf("load:done\n");
                
                strcpy(stdout,"Pi:Ok");
                piexchangebyte(ENDTRANSFER);
            }
        }
        
        free(buf);
        
    } else {
        rc = RC_FILENOTFOUND;
        piexchangebyte(RC_FAILED);
        strcpy(stdout,"Pi:Error opening file");
    }
    
    printf("load:sending stdout %s\n",stdout);
    dataInfo = senddatablock(stdout,strlen(stdout)+1,true);
    
    free(tokens);
    free(stdout);
    free(newpath);
    
    printf("load:exiting rc = %x\n",rc);
    return rc;
    
}

int loadbin(char *msxcommand) {
    int rc;
    FILE *fp;
    int filesize,index,blocksize,retries;
    unsigned char *buf;
    char *stdout;
    unsigned char mymsxbyte;
    char** tokens;
    transferStruct dataInfo;
    
    //printf("loadbin:starting %s\n",msxcommand);
    
    tokens = str_split(msxcommand,' ');
    printf("loadbin:parsed command is %s %s\n",*(tokens),*(tokens + 1));
    
    rc = RC_UNDEFINED;
    
    fp = fopen(*(tokens + 1),"rb");
    if (fp) {
        fseek(fp, 0L, SEEK_END);
        filesize = ftell(fp);
        rewind(fp);
        buf = malloc(sizeof(*buf) * filesize);
        fread(buf,filesize,1,fp);
        fclose(fp);
        
        index = 0;
        
        if (*(buf)!=0xFE) {
            printf("loadbin:Not a .bin program. Aborting\n");
            rc = RC_UNDEFINED;
            stdout = malloc(sizeof(*stdout) * 19);
            strcpy(stdout,"Pi:Not a .bin file");
            piexchangebyte(ABORT);
        } else {
            
            piexchangebyte(STARTTRANSFER);
            
            // send to msx the total size of file
            printf("load:sending file size %i\n",filesize - 7);
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
            
            printf("loadbin:Start address = %02x%02x Exec address = %02x%02x\n",*(buf+2),*(buf+1),*(buf+4),*(buf+3));
            
            printf("loadbin:calling senddatablock\n");
            
            // now send 512 bytes at a time.
            
            if (filesize>512) blocksize = 512; else blocksize = filesize;
            while(blocksize) {
                retries=0;
                dataInfo.rc = RC_UNDEFINED;
                while(retries<GLOBALRETRIES && dataInfo.rc != RC_SUCCESS) {
                    dataInfo.rc = RC_UNDEFINED;
                    dataInfo = senddatablock(buf+index,blocksize,true);
                    printf("loadbin:index = %i blocksize = %i retries:%i rc:%x\n",index,blocksize,retries,dataInfo.rc);
                    retries++;
                    rc = dataInfo.rc;
                }
                
                // Transfer interrupted due to CRC error
                if(retries>GLOBALRETRIES) break;
                
                index += blocksize;
                if (filesize - index > 512) blocksize = 512; else blocksize = filesize - index;
            }
            
            printf("loadbin:(exited) index = %i blocksize = %i retries:%i rc:%x\n",index,blocksize,retries,dataInfo.rc);
            mymsxbyte = piexchangebyte(ENDTRANSFER);
            
            if(retries>=GLOBALRETRIES || rc != RC_SUCCESS) {
                printf("loadbin:Error during data transfer:%x\n",rc);
                rc = RC_CRCERROR;
                stdout = malloc(sizeof(*stdout) * 13);
                
                strcpy(stdout,"Pi:CRC Error");
            } else {
                printf("load:done\n");
                stdout = malloc(sizeof(*stdout) * 15);
                strcpy(stdout,"Pi:File loaded");
            }
            
            mymsxbyte = piexchangebyte(ENDTRANSFER);
            
        }
        
        free(buf);
        
    } else {
        printf("loadbin:error opening file\n");
        rc = RC_FILENOTFOUND;
        mymsxbyte = piexchangebyte(ABORT);
        stdout = malloc(sizeof(*stdout) * 22);
        strcpy(stdout,"Pi:Error opening file");
    }
    
   // if (rc!=RC_SUCCESS) {
        printf("load:sending stdout: size=%i, %s\n",strlen(stdout)+1,stdout);
        dataInfo = senddatablock(stdout,strlen(stdout)+1,true);
    //}
    
    free(tokens);
    free(stdout);
    
    printf("loadbin:exiting rc = %x\n",rc);
    return rc;
    
}

int msxdos_secinfo(DOS_SectorStruct *sectorInfo) {
    unsigned char byte_lsb, byte_msb;
    int mymsxbyte=0;
    
    int rc = 1;
    
    //printf("msxdos_secinfo: Starting\n");
    //while(rc) {
    // mymsxbyte = piexchangebyte(SENDNEXT);
    //   if (mymsxbyte==SENDNEXT || mymsxbyte<0) rc=false;
    //}
    
    mymsxbyte = piexchangebyte(SENDNEXT);
    
    if (mymsxbyte == SENDNEXT) {
        //printf("msxdos_secinfo: received SENDNEXT\n");
        sectorInfo->deviceNumber = piexchangebyte(SENDNEXT);
        sectorInfo->sectors = piexchangebyte(SENDNEXT);
        sectorInfo->logicUnitNumber = piexchangebyte(SENDNEXT);
        byte_lsb = piexchangebyte(SENDNEXT);
        byte_msb = piexchangebyte(SENDNEXT);
        
        sectorInfo->initialSector = byte_lsb + 256 * byte_msb;
        
        //printf("msxdos_secinfo:deviceNumber=%x logicUnitNumber=%x #sectors=%x sectorInfo->initialSector=%i\n",sectorInfo->deviceNumber,sectorInfo->logicUnitNumber,sectorInfo->sectors,sectorInfo->initialSector);
        
        if (sectorInfo->deviceNumber == -1 || sectorInfo->sectors == -1 || sectorInfo->logicUnitNumber == -1 || byte_lsb == -1 || byte_msb == -1)
            rc = RC_FAILED;
        else
            rc = RC_SUCCESS;
    } else {
        printf("msxdos_secinfo:sync_transf error\n");
        rc = RC_OUTOFSYNC;
    }
    
    //printf("msxdos_secinfo:exiting rc = %x\n",rc);
    return rc;
    
}


int msxdos_readsector(unsigned char *currentdrive,DOS_SectorStruct *sectorInfo) {
    
    int rc,numsectors,initsector;
    
    numsectors = sectorInfo->sectors;
    initsector = sectorInfo->initialSector;
    
    debug = 0;
    // now tansfer sectors to MSX, 512 bytes at a time and perform sync betwen blocks
    //printf("msxdos_readsector:calling secsenddata\n");
    //printf("msxdos_readsector:Starting with #sectors:%i and initsector:%i\n",numsectors,initsector);
    rc = secsenddata(currentdrive+(initsector*512),numsectors*512);
    
    debug = 0;
    
    //printf("msxdos_readsector:exiting rc = %x\n",rc);
    
    return rc;
    
}

int msxdos_writesector(unsigned char *currentdrive,DOS_SectorStruct *sectorInfo) {
    
    int rc,sectorcount,numsectors,initsector,index;
    
    numsectors = sectorInfo->sectors;
    initsector = sectorInfo->initialSector;
    
    printf("msxdos_writesector:Starting with #sectors:%i and initsector:%i\n",numsectors,initsector);
    
    
    index = 0;
    sectorcount = numsectors;
    // Read data from MSX
    while(sectorcount) {
        rc = secrecvdata(currentdrive+index+(initsector*512));
        if (rc!=RC_SUCCESS) break;
        index += 512;
        sectorcount--;
    }
    
    
     if (rc==RC_SUCCESS) {
     printf("msxdos_writesector:Success transfering data sector\n");
     } else {
     printf("msxdos_writesector:Error transfering data sector\n");
     }
    
    
    printf("msxdos_writesector:exiting rc = %x\n",rc);
    
    return rc;
}

int pnewdisk(char * msxcommand, char *dsktemplate) {
    char** tokens;
    struct stat diskstat;
    unsigned char *stdout;
    char *cpycmd;
    int rc;
    FILE *fp;
    
    printf("pnewdisk:starting %s\n",msxcommand);
    
    tokens = str_split(msxcommand,' ');
    
    stdout = malloc(sizeof(*stdout) * 40);
    
    rc = RC_FAILED;
    
    if (*(tokens + 1) != NULL) {
        
        cpycmd = malloc(sizeof(*cpycmd) * 140);
        
        printf("pnewdisk:Creating new dsk file: %s\n",*(tokens + 1));
        
        
        sprintf(cpycmd,"cp %s %s",dsktemplate,*(tokens + 1));
        
        if(fp = popen(cpycmd, "r")) {
            fclose(fp);
            
            // check if file was created
            if( access( *(tokens + 1), F_OK ) != -1 ) {
                sprintf(cpycmd,"chown pi.pi %s",*(tokens + 1));
                fp = popen(cpycmd, "r");
                fclose(fp);
                strcpy(stdout,"Pi:Ok");
                rc = RC_SUCCESS;
            } else
                strcpy(stdout,"Pi:Error verifying disk");
        } else
            strcpy(stdout,"Pi:Error creating disk");
        
        free(cpycmd);
        
    } else
        strcpy(stdout,"Pi:Error\nSyntax: pnewdisk <file>");
    
    senddatablock(stdout,strlen(stdout)+1,true);
    
    free(tokens);
    free(stdout);
    printf("pnewdisk:Exiting with rc=%x\n",rc);
    return rc;
    
}

int msxdos_format(struct DiskImgInfo *driveInfo) {
    FILE *fp;
    int rc;
    
    char *cpycmd;
    
    cpycmd = malloc(sizeof(unsigned char) * 140);
    
    sprintf(cpycmd,"mkfs -t msdos -F 12 %s",driveInfo->dskname);
    
    printf("msxdos_format:Formating drive: %s\n",cpycmd);
    
    // run mkfs command using popen()"
    if(fp = popen(cpycmd, "r")) {
        fclose(fp);
        piexchangebyte(ENDTRANSFER);
        rc = RC_SUCCESS;
    } else {
        piexchangebyte(ABORT);
        rc = RC_FAILED;
    }
    
    free(cpycmd);
    printf("msxdos_format:Exiting with rc=%x\n",rc);
    return rc;
}

int * msxdos_inihrd(struct DiskImgInfo *driveInfo) {
    
    int rc,fp;
    struct   stat diskstat;
    
    printf("msxdos_inihrd:Initializing drive:%i\n",driveInfo->deviceNumber);
    
    driveInfo->rc = RC_FAILED;
    
    if( access( driveInfo->dskname, F_OK ) != -1 ) {
        printf("msxdos_inihrd:Mounting disk image 1:%s\n",driveInfo->dskname);
        fp = open(driveInfo->dskname,O_RDWR);
        
        if (stat(driveInfo->dskname, &diskstat) == 0) {
            driveInfo->size = diskstat.st_size;
            if ((driveInfo->data = mmap((caddr_t)0, driveInfo->size, PROT_READ | PROT_WRITE, MAP_SHARED, fp, 0))  == (caddr_t) -1) {
                printf("msxdos_inihrd:Disk image failed to mount\n");
            } else {
                printf("msxdos_inihrd:Disk mapped in ram with size %i Bytes\n",driveInfo->size);
                driveInfo->rc = RC_SUCCESS;
            }
        } else {
            printf("msxdos_inihrd:Error getting disk image size\n");
        }
    } else {
        printf("msxdos_inihrd:Disk image not found\n");
    }
    
    return driveInfo->rc;
}

struct DiskImgInfo psetdisk(char * msxcommand) {
    struct DiskImgInfo diskimgdata;
    char** tokens;
    struct   stat diskstat;
    char *stdout;
    
    printf("psetdisk:starting %s\n",msxcommand);
    
    tokens = str_split(msxcommand,' ');
    stdout = malloc(sizeof(*stdout) * 64);
    
    if ((*(tokens + 2) != NULL) && (*(tokens + 1) != NULL)) {
        
        diskimgdata.rc = RC_SUCCESS;
        
        if(strcmp(*(tokens + 1),"0")==0)
            diskimgdata.deviceNumber = 0;
        else if (strcmp(*(tokens + 1),"1")==0)
            diskimgdata.deviceNumber = 1;
        else
            diskimgdata.rc = RC_FAILED;
        
        if (diskimgdata.rc != RC_FAILED) {
            strcpy(diskimgdata.dskname,*(tokens + 2));
            printf("psetdisk:Disk image is:%s\n",diskimgdata.dskname);
            
            if( access( diskimgdata.dskname, F_OK ) != -1 ) {
                printf("psetdisk:Found disk image\n");
                strcpy(stdout,"Pi:OK");
            } else {
                printf("psetdisk:Disk image not found.\n");
                diskimgdata.rc = RC_FAILED;
                strcpy(stdout,"Pi:Error\nDisk image not found");
            }
        } else {
            printf("psetdisk:Invalid device\n");
            diskimgdata.rc = RC_FAILED;
            strcpy(stdout,"Pi:Error\nInvalid device\nDevice must be 0 or 1");
        }
    } else {
        printf("psetdisk:Invalid parameters\n");
        diskimgdata.rc = RC_FAILED;
        strcpy(stdout,"Pi:Error\nSyntax: psetdisk <0|1> <file>");
    }
    
    senddatablock(stdout,strlen(stdout)+1,true);
    free(tokens);
    free(stdout);
    
    return diskimgdata;
}

int pset(struct psettype *psetvar, char *msxcommand) {
    int rc;
    char** tokens;
    char *stdout;
    int n;
    bool found = false;
    
    printf("pset:starting %s\n",msxcommand);
    
    tokens = str_split(msxcommand,' ');
    stdout = malloc(sizeof(*stdout) * 64);
    strcpy(stdout,"Pi:Ok");
    
    rc = RC_SUCCESS;
    
    
    if ((*(tokens + 1) == NULL)) {
        printf("pset:missing parameters\n");
        strcpy(stdout,"Pi:Error\nSyntax: pset display | <variable> <value>\n");
    } else if ((*(tokens + 2) == NULL)) {
        
        //DISPLAY is requested?
        if ((strncmp(*(tokens + 1),"display",1)==0) ||
            (strncmp(*(tokens + 1),"DISPLAY",1)==0)) {
            
            //printf("pcd:generating output for DISPLAY\n");
            stdout = realloc(stdout,sizeof(*stdout) * (10*16 + 10*255) + 12);
            strcpy(stdout,"\n");
            for(n=0;n<10;n++) {
                strcat(stdout,psetvar[n].var);
                strcat(stdout,"=");
                strcat(stdout,psetvar[n].value);
                strcat(stdout,"\n");
            }
            
        } else {
            printf("pset:missing parameters\n");
            strcpy(stdout,"Pi:Error\nSyntax: pset <variable> <value>\n");
        }
    } else {
        
        printf("pset:setting %s to %s\n",*(tokens+1),*(tokens+2));
        
        for(n=0;n<10;n++) {
            printf("psetvar[%i]=%s\n",n,psetvar[n].var);
            if (strcmp(psetvar[n].var,*(tokens +1))==0) {
                strcpy(psetvar[n].value,*(tokens +2));
                found = true;
                break;
            }
        }
        
        if (!found) {
            for(n=0;n<10;n++) {
                //printf("psetvar[%i]=%s\n",n,psetvar[n].var);
                if (strcmp(psetvar[n].var,"free")==0) {
                    strcpy(psetvar[n].var,*(tokens +1));
                    strcpy(psetvar[n].value,*(tokens +2));
                    break;
                }
            }
        }
        if (n==10) {
            printf("pset:All slots are taken\n");
            strcpy(stdout,"Pi:Error\nAll slots are taken\n");
        }
    }
    
    senddatablock(stdout,strlen(stdout)+1,true);
    
    free(stdout);
    free(tokens);
    return rc;
}

int pwifi(char * msxcommand, char *wifissid, char *wifipass) {
    int rc;
    char** tokens;
    char *stdout;
    char *buf;
    int i;
    FILE *fp;
    
    rc = RC_FAILED;
    stdout = malloc(sizeof(*stdout) * 128);
    tokens = str_split(msxcommand,' ');
    
    if ((*(tokens + 1) == NULL)) {
        printf("pset:missing parameters\n");
        strcpy(stdout,"Pi:Error\nSyntax: pwifi display | set");
        piexchangebyte(RC_FAILED);
        senddatablock(stdout,strlen(stdout)+1,true);
    } else if ((strncmp(*(tokens + 1),"DISPLAY",1)==0) ||
               (strncmp(*(tokens + 1),"display",1)==0)) {
        
        rc = runpicmd("ifconfig wlan0 | grep inet >/tmp/msxpi.tmp");
        
    } else if ((strncmp(*(tokens + 1),"SET",1)==0) ||
               (strncmp(*(tokens + 1),"set",1)==0)) {
        
        buf = malloc(sizeof(*buf) * 256);
        fp = fopen("/etc/wpa_supplicant/wpa_supplicant.conf", "w+");
        
        strcpy(buf,"country=GB\n\nctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\nupdate_config=1\nnetwork={\n");
        strcat(buf,"\tssid=\"");
        strcat(buf,wifissid);
        strcat(buf,"\"\n\tpsk=\"");
        strcat(buf,wifipass);
        strcat(buf,"\"\n}\n");
        
        fprintf(fp,buf);
        fclose(fp);
        free(buf);
        
        rc = runpicmd("ifdown wlan0 && ifup wlan0");
    } else {
        printf("pset:Invalid parameters\n");
        strcpy(stdout,"Pi:Error\nSyntax: pwifi display | set");
        piexchangebyte(RC_FAILED);
        senddatablock(stdout,strlen(stdout)+1,true);
    }
    
    free(tokens);
    free(stdout);
    
    printf("pwifi:Exiting with rc=%x\n",rc);
    return rc;
    
}

int pcd(struct psettype *psetvar,char * msxcommand) {
    int rc;
    struct stat diskstat;
    char** tokens;
    char *stdout;
    char *newpath;
    int i;
    
    printf("pcd:path is %s\n",msxcommand);
    
    rc = RC_SUCCESS;
    if (piexchangebyte(RC_WAIT)!=SENDNEXT) {
        printf("pdir:out of sync\n");
        return RC_FAILED;
    }
    
    if ((strlen(msxcommand)<5) || (strcmp(msxcommand,"PCD ..")==0) || (strcmp(msxcommand,"pcd ..")==0)) {
        
        piexchangebyte(RC_FAILED);
        
        stdout = malloc((strlen(psetvar[0].value)*sizeof(*stdout))+1);
        // pcd without parameters should go to home?
        //strcpy(psetvar[0].value,HOMEPATH);
        sprintf(stdout,"%s\n",psetvar[0].value);
        senddatablock(stdout,strlen(stdout)+1,true);
        printf("pcd:PCD empty or invalid - exiting with rc=%x\n",rc);
        free(stdout);
        return rc;
    }
    
    tokens = str_split(msxcommand,' ');
    
    stdout = malloc(255 * sizeof(*stdout));
    
    
    //printf("pcd:debug tokens0 = %s\n",*(tokens + 0));
    //printf("pcd:debug tokens1 = %s\n",*(tokens + 1));
    
    // Deals with absolute local filesystem PATHs
    //if cd has no parameter (want to go home)
    if (*(tokens + 1)==NULL) {
        printf("pcd:going local home\n");
        strcpy(psetvar[0].value,HOMEPATH);
        sprintf(stdout,"%s\n",HOMEPATH);
        
        //DISPLAY is requested?
    } else if ((strncmp(*(tokens + 1),"display",7)==0) ||
               (strncmp(*(tokens + 1),"DISPLAY",7)==0)) {
        
        printf("pcd:generating output for DISPLAY\n");
        stdout = realloc(stdout, ((10*16 + 10*255) * sizeof(*stdout)) + 1);
        strcpy(stdout,"\n");
        for(i=0;i<10;i++) {
            strcat(stdout,psetvar[0].var);
            strcat(stdout,"=");
            strcat(stdout,psetvar[0].value);
            strcat(stdout,"\n");
        }

        rc = RC_SUCCESS;
        
        //error if path is too long (> 128)
    } else if (strlen(*(tokens + 1))>128) {
        printf("pcd:path is too long\n");
        strcpy(stdout,"Pi:Error: Path is too long\n");
        rc = RC_FAILED;
        
        
        //if start with "/<ANYTHING>"
    } else if (strncmp(*(tokens + 1),"/",1)==0) {
        printf("pcd:going local root /\n");
        if( access( *(tokens + 1), F_OK ) != -1 ) {
            strcpy(psetvar[0].value,*(tokens + 1));
            sprintf(stdout,"%s\n",*(tokens + 1));
        } else {
            strcpy(stdout,"Pi:Error: Path does not exist\n");
            rc = RC_FAILED;
        }
        
    } else if ((strncmp(*(tokens + 1),"http:",5)==0) ||
               (strncmp(*(tokens + 1),"ftp:",4)==0) ||
               (strncmp(*(tokens + 1),"smb:",4)==0) ||
               (strncmp(*(tokens + 1),"nfs:",4)==0)) {
        
        printf("pcd:absolute remote path / URL\n");
        strcpy(psetvar[0].value,*(tokens + 1));
        sprintf(stdout,"%s\n",*(tokens + 1));
        
        // is resulting path too long?
    } else if ((strlen(psetvar[0].value)+strlen(*(tokens + 1))+2) >254) {
        printf("pcd:Resulting path is too long\n");
        strcpy(stdout,"Pi:Error: Resulting path is too long\n");
        rc = RC_FAILED;
        
        // is relative path
        // is current PATH a remote PATH / URL?
    } else if ((strncmp(psetvar[0].value,"http:",5)==0)||
               (strncmp(psetvar[0].value,"ftp:",4)==0) ||
               (strncmp(psetvar[0].value,"smb:",4)==0) ||
               (strncmp(psetvar[0].value,"nfs:",4)==0)) {
        
        printf("pcd:append to relative remote path / URL\n");
        sprintf(psetvar[0].value,"%s/%s",psetvar[0].value,*(tokens + 1));
        sprintf(stdout,"%s\n",psetvar[0].value);
        
    } else {
        newpath = malloc((sizeof(*newpath) * (strlen(psetvar[0].value)+strlen(*(tokens + 1)))) + 1);
        strcpy(newpath,psetvar[0].value);
        strcat(newpath,"/");
        strcat(newpath,*(tokens + 1));
        
        printf("pcd:append to relative path. final path is %s\n",newpath);
        
        if( access( newpath, F_OK ) != -1 ) {
            strcpy(psetvar[0].value,newpath);
            sprintf(stdout,"%s\n",newpath);
        } else {
            strcpy(stdout,"Pi:Error: Path does not exist\n");
            rc = RC_FAILED;
        }
        
        printf("pcd:append to relative path: result is %s\n",stdout);
        
        free(newpath);
    }
    
    
    printf("pcd:sending stdout %s with %i bytes\n",stdout,strlen(stdout));
    
    if (piexchangebyte(RC_SUCCESS)!=SENDNEXT) {
        printf("pdir:out of sync\n");
        return RC_FAILED;
    }
    senddatablock(stdout,strlen(stdout)+1,true);
    
    free(tokens);
    printf("freeing memory-stdout - this locks down the server, must be fixed.\n");
    //free(stdout);
    printf("pcd:Exiting with rc=%x\n",rc);
    return rc;
    
}

int pdir(struct psettype *psetvar, char *msxcommand) {
    int rc;
    MemoryStruct chunk;
    MemoryStruct *chunkptr = &chunk;
    char *buf;
    char *theurl;
    
    printf("pdir:starting command:%s\n",msxcommand);
    
    if (piexchangebyte(RC_WAIT)!=SENDNEXT) {
        printf("pdir:out of sync\n");
        return RC_FAILED;
    }
    
    // is current PATH a remote PATH / URL?
    
    if ((strncmp(psetvar[0].value,"ftp:",4)==0) ||
        (strncmp(psetvar[0].value,"smb:",4)==0) ||
        (strncmp(psetvar[0].value,"nfs:",4)==0)) {
        
        printf("pdir:remote ftp/smb/nfs path:%s\n",psetvar[0].value);
        
        chunk.memory = malloc(1);
        chunk.size = 0;
        
        theurl = malloc((strlen(psetvar[0].value)*sizeof(*theurl))+1);
        strcpy(theurl,psetvar[0].value);
        strcat(theurl,"/");
        
        rc = loadfile_remote(theurl,chunkptr);
        free(theurl);
        
        printf("pdir: curl returned %s\n",chunk.memory);
        
        if (rc==RC_SUCCESS) {
            printf("pdir:listing generated, size is: %i\n",chunk.size);
            if (piexchangebyte(RC_SUCCESS)==SENDNEXT) {
                senddatablock(chunk.memory,chunk.size,true);
            } else {
                printf("pdir:out of sync\n");
            }

        } else {
            printf("pdir:listing error\n");
            if (piexchangebyte(RC_FAILED)==SENDNEXT) {
                strcpy(chunk.memory,"Pi:Error");
                senddatablock(chunk.memory,9,true);
            }
        }
    
        free(chunk.memory);
        
    } else if (strncmp(psetvar[0].value,"http",4)==0) {
        printf("pdir:remote http path:%s\n",psetvar[0].value);
        buf = malloc(255 * sizeof(*buf));
        
        sprintf(buf,"/usr/bin/wget --no-check-certificate  -O /tmp/msxpifile1.tmp -o /tmp/msxpi_error.log %s",psetvar[0].value);
        /*
        strcpy(buf,"wget --no-check-certificate  -O /tmp/msxpifile1.tmp -o /tmp/msxpi_error.log ");
        strcat(buf,psetvar[0].value);
        */
        
        printf("pdir:running %s\n",buf);
        system(buf);
        
        sprintf(buf,"/bin/cat /tmp/msxpifile1.tmp|/usr/bin/html2text -width %s > /tmp/msxpi.tmp",psetvar[3].value);
        
        /*
        strcpy(buf,"/bin/cat /tmp/msxpifile1.tmp|/usr/bin/html2text -width ");
        strcat(buf,psetvar[3].value);
        strcat(buf," > /tmp/msxpi.tmp");
        */
        
        printf("pdir:running %s\n",buf);
        system(buf);
        
        printf("pdir:freeing buf\n");
        free(buf);
        
        printf("pdir:send output to msx via runpicmd\n");
        rc = runpicmd("cat /tmp/msxpi.tmp");
        
    } else {
        printf("pdir:local path:");
        
        strcpy(msxcommand,"ls ");
        strcat(msxcommand,psetvar[0].value);
               
        printf("%s\n",msxcommand);
        
        // piexchangebyte is not here because runpicm has it already
        rc = runpicmd(msxcommand);
        
    }
    
    printf("pdir:Exiting with rc=%x\n",rc);
    return rc;
               
}

static size_t
WriteMemoryCallback(void *contents, size_t size, size_t nmemb, void *userp)
{
    size_t realsize = size * nmemb;
    MemoryStruct *mem = (MemoryStruct *)userp;
    
    mem->memory = realloc(mem->memory, mem->size + realsize + 1);
    if(mem->memory == NULL) {
        /* out of memory! */
        printf("not enough memory (realloc returned NULL)\n");
        return 0;
    }
    
    memcpy(&(mem->memory[mem->size]), contents, realsize);
    mem->size += realsize;
    mem->memory[mem->size] = 0;
    
    return realsize;
}

int loadfile_local(char *theurl,MemoryStruct *chunk) {
    FILE *fd;
    char *fname = malloc(sizeof(char) * strlen(theurl) + 1);
    
    //strcpy(fname,theurl+7);
    strcpy(fname,theurl);
    
    printf("loadfile_local:Starting with url ->:%s\n",theurl);

    //Open file
    fd = fopen(fname, "rb");
    printf("loadfile_local:after fopen\n");
    if (!fd) {
        fprintf(stderr, "Unable to open file %s", fname);
        return RC_FAILED;
    }
    
    printf("loadfile_local:after fopen if\n");
    
    //Get file length
    fseek(fd, 0, SEEK_END);
    printf("loadfile_local:after fseek\n");
    chunk->size=ftell(fd);
    printf("loadfile_local:after ftell\n");
    fseek(fd, 0, SEEK_SET);
    
    printf("loadfile_local:File size is:%i\n",chunk->size);
    
    //Allocate memory
    chunk->memory = (char *)realloc(chunk->memory,chunk->size + 1);
    if (!chunk->memory) {
        fprintf(stderr, "Memory error!");
        fclose(fd);
        return RC_FAILED;
    }
    
    //Read file contents into buffer
    fread(chunk->memory, chunk->size, 1, fd);
    fclose(fd);
    
    printf("loadfile_local:Exiting with rc=RC_SUCCESS\n");
    return RC_SUCCESS;
    
}

int loadfile_remote(char *theurl, MemoryStruct *chunk) {
    
    int rc = RC_FAILED;
    CURL *curl_handle;
    CURLcode res;
    long curl_code = 0;
    
    printf("loadfile_remote:Starting:%s\n",theurl);
    curl_global_init(CURL_GLOBAL_ALL);
    
    curl_handle = curl_easy_init();
    
    // parse the protocol
    
    curl_easy_setopt(curl_handle, CURLOPT_URL, theurl);
    
    curl_easy_setopt(curl_handle, CURLOPT_URL, theurl);
    curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, WriteMemoryCallback);
    curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, (void *)chunk);
    //curl_easy_setopt(curl_handle, CURLOPT_USERAGENT, "libcurl-agent/1.0");
    curl_easy_setopt(curl_handle, CURLOPT_USERAGENT, "Mozilla/4.0");
    
    //if(authreq)
    //    curl_easy_setopt(curl_handle, CURLOPT_USERPWD, "msxpi@retro-cpu.run:retro-cpu.run");
    
    res = curl_easy_perform(curl_handle);
    curl_easy_getinfo (curl_handle, CURLINFO_RESPONSE_CODE, &curl_code);
    printf("loadfile_remote:loadfile_remote error code:%lu\n",curl_code);
    
    if(curl_code==200||curl_code==226)
        rc = RC_SUCCESS;
    else
        rc = curl_code;
    
    curl_easy_cleanup(curl_handle);
    curl_global_cleanup();
    
    printf("loadfile_remote:Exiting with rc=%i\n",rc);
    
    return rc;
}

int uploaddata(unsigned char *data, size_t totalsize, int index) {
    int rc,crc,bytecounter,myblocksize,msxblocksize;
    unsigned char mypibyte,mymsxbyte;
    
    printf("uploaddata: Sending STARTTRANSFER\n");
    
    mymsxbyte=piexchangebyte(STARTTRANSFER);
    if (mymsxbyte != STARTTRANSFER) {
        printf("uploaddata: Received %x\n",mymsxbyte);
        return RC_OUTOFSYNC;
    }
    
    printf("uploaddata:blocksize - ");
    // read blocksize, MAXIMUM 65535 KB
    msxblocksize = piexchangebyte(SENDNEXT) + 256 * piexchangebyte(SENDNEXT);
    myblocksize = msxblocksize;
    
    //Now verify if has finished transfering data
    if (index*msxblocksize >= totalsize) {
        piexchangebyte(ENDTRANSFER);
        return ENDTRANSFER;
    }
    
    piexchangebyte(SENDNEXT);
    
    printf("recv:%i ",msxblocksize);
    // send back to msx the block size, or the actual file size if blocksize > totalsize
    if (totalsize <= index*msxblocksize+msxblocksize)
        myblocksize = totalsize - (index*msxblocksize);
    
    printf("sent:%i\n",myblocksize);
    
    printf("uploaddata:totalsize is %i, this block is %i, block end is %i\n",totalsize,index*msxblocksize,index*msxblocksize+myblocksize);
    
    piexchangebyte(myblocksize % 256); piexchangebyte(myblocksize / 256);
    
    crc = 0;
    bytecounter = 0;
    
    printf("uploaddata: Loop to send block\n");
    while(bytecounter<myblocksize) {
        mypibyte = *(data + (index*myblocksize) + bytecounter);
        piexchangebyte(mypibyte);
        crc ^= mypibyte;
        bytecounter++;
    }
    
    
    // exchange crc
    mymsxbyte=piexchangebyte(crc);
    if (mymsxbyte == crc)
        rc = RC_SUCCESS;
    else
        rc = RC_CRCERROR;
    
    printf("uploaddata:local crc: %x / remote crc:%x\n",crc,mymsxbyte);
    
    printf("uploaddata:exiting rc = %x\n",rc);
    
    return rc;
    
}

int pcopy(struct psettype *psetvar, char *msxcommand, MemoryStruct *chunkptr) {
    char** tokens;
    char *stdout;
    char *theurl, *fullurl;
    int rc,fidpos,transftype;
    transferStruct dataInfo;
    
    tokens = str_split(msxcommand,' ');
    
    stdout = malloc(sizeof(*stdout) * 60);
    
    fidpos = 1; // token position for source file name

    // verify if all required parameters are present
    printf("fidpos %i\n",fidpos);
    if ((*(tokens + fidpos) == NULL) ||
        (*(tokens + fidpos + 1)) == NULL) {
        printf("pcopy:missing parameters\n");
        piexchangebyte(RC_FAILED);
        strcpy(stdout,"Pi:Error\nSyntax: pcopy <source url> <target file>\n");
        printf("%i\n",strlen(stdout));
        senddatablock(stdout,strlen(stdout)+1,true);
        free(stdout);
        return RC_FAILED;
    }
    
    // SYNC TO SEND FILENAME
    if (piexchangebyte(SENDNEXT) != SENDNEXT) {
        return RC_OUTOFSYNC;
    }
    
    // send file name
    printf("pcopy:Sending filename: %s\n",*(tokens + fidpos + 1));
    //if (saveoption)
    dataInfo = senddatablock(*(tokens + fidpos + 1),strlen(*(tokens + fidpos + 1))+1,true);

    printf("pcopy:returned from senddatablock sendname ");
    if (dataInfo.rc != RC_SUCCESS) {
        printf("with FAILURE\n");
        free(tokens);
        free(stdout);
        return dataInfo.rc;
    }
    
    printf("with SUCCESS\n");

    theurl = malloc(sizeof(*theurl) * strlen(*(tokens + fidpos))+1);
    //chunk.memory = malloc(1);
    //chunk.size = 0;
    
    // send WAIT to MSX
    piexchangebyte(RC_WAIT);
    
    strcpy(theurl,*(tokens + fidpos));
    
    //printf("pcopy:Reading file into memory:%s\n");
    
    transftype = 0;
    if (strncmp(psetvar[0].value,"/",1)==0) {
        
        printf("pcopy:local file\n");
        fullurl = malloc(256*sizeof(*fullurl));
        strcpy(fullurl,psetvar[0].value);
        strcat(fullurl,"/");
        strcat(fullurl,theurl);
        rc = loadfile_local(fullurl,chunkptr);
        
    } else if (strncmp(*(tokens + fidpos + 1),"FILE://",7)==0) {
        transftype = 1;
        //rc = loadfile_frommsx(theurl,chunkptr);
    } else {
        printf("pcopy:remote file\n");
        fullurl = malloc(256*sizeof(*fullurl));
        strcpy(fullurl,psetvar[0].value);
        strcat(fullurl,"/");
        strcat(fullurl,theurl);
        rc = loadfile_remote(fullurl,chunkptr);
        printf("pcopy:loadfile_remote returned rc=%x\n",rc);
        free(fullurl);
    }
    
    printf("Buffer size:%i\n",chunkptr->size);
    //printf("Buffer data:%s\n",chunkptr->memory);
    
    printf("pcopy:returned from getfile ");
    if (rc != RC_SUCCESS) {
        printf("with FAILURE\n");
        piexchangebyte(RC_FAILED);
        sprintf(stdout,"Pi:Error with httpcode: %i",rc);
        senddatablock(stdout,30,true);
        free(tokens);
        free(stdout);
        free(theurl);
        return rc;
    }
    
    printf("with success\n");
    piexchangebyte(RC_SUCCESS);
    
    free(tokens);
    free(stdout);
    free(theurl);
    
    printf("pcopy:Exiting with rc=%x\n",rc);
    return rc;
    
}

int nfs_8dot3(char *strin, char ***strout){
    char name[8];
    char ext[4];
    int len1,len2;
    char** tokens;
    
    printf("nfs_8dot3:starting\n");
    memset(strout,32,25);
    
    tokens = str_split(strin,'.');
    if (*(tokens + 1)==NULL)
        sprintf(strout," %-8s    ",*(tokens + 0));
    else {
        len1=strlen(*(tokens + 0));
        len2=strlen(*(tokens + 1));
        
        sprintf(strout," %-.8s.%-.3s",*(tokens + 0),*(tokens + 1));
        
        printf("nfs_8dot3:>%s<\n",strout);
    }
    
    memset(strout+14,0,1);
    printf("nfs_8dot3:Returning:>%s<,len=%i\n",strout,strlen(strout));
    free(tokens);
}

char * nfs_setfname(char curpath[254],char *msxpath) {
    char localpath[254];
    char localthisfile[254];
    long filesize;
    struct stat st;
    struct tm *sttime;
    
    int dst,i;
    char **tokens;
    
    printf("nfs_setfname:starting\n");
    
    printf("nfs_setfname:curpath=%s msxpath=%s\n",curpath,msxpath);
    
    if ((*msxpath)=='/')
        strcpy(localpath,msxpath);
    else {
        strcpy(localpath,curpath);
        strcat(localpath,"/");
        strcat(localpath,msxpath);
    }
    
    printf("nfs_setfname:final path: %s\n",localpath);
    
    dst = stat(localpath, &st);
    
    if(dst != 0) {
        printf("nfs_setfname:file not found\n");
        return 1;
    }
    
    
    if (((*msxpath)!='.') && (strcmp(msxpath,"..")!=0)) {
        
        printf("spliting\n");
        
        if (strstr(msxpath,"/")!=NULL) {
            tokens = str_split(msxpath,'/');
            for(;*(tokens+i)!=NULL;i++) {};
            
            nfs_8dot3(*(tokens+i-1),&localthisfile);
        } else
            // format filename to 8.3 characters and terminate with zero
            nfs_8dot3(msxpath,&localthisfile);
        
    } else {
        strcpy(localthisfile," ");
        strcat(localthisfile,msxpath);
    }
    
    //memset(localthisfile+13,0,1);
    
    // set file attributes
    // enable bit4 when directory
    if (isDirectory(localpath))
        memset(localthisfile+14,16,1);
    else
        memset(localthisfile+14,0,1);
    
    
    // set time attributes
    sttime = gmtime(&(st.st_mtime));
    int minute = sttime->tm_min;
    int second = 0;
    int hour = sttime->tm_hour+TZ;
    int day = sttime->tm_mday;
    int month = (sttime->tm_mon) + 1;
    int year = (sttime->tm_year)-20;
    
    int f15 = ((minute & 7) << 5) | (second / 2);
    int f16 = (hour << 3) | (minute >> 3);
    int f17 = (month << 5) | day;
    int f18 = ((year - 1980) << 1) | (month >> 3);
    
    memset(localthisfile+15,f15,1);
    memset(localthisfile+16,f16,1);
    memset(localthisfile+17,f17,1);
    memset(localthisfile+18,f18,1);
    
    // get file size
    // This need rethingking to store as litle endian value - if not already.
    memset(localthisfile+21,0,4);
    filesize = st.st_size;
    
    *(localthisfile+21) = filesize & 0xff;
    *(localthisfile+22) = filesize>>8 & 0xff;
    *(localthisfile+23) = filesize>>16 & 0xff;
    *(localthisfile+24) = filesize>>24 & 0xff;
    
    printf("nfs_setfname:Returning:%s\n",localthisfile+1);
    
    return &localthisfile;
    
}

void dos_ffirst(char *curpath,char *msxpath) {
    
    int count = 0;
    size_t length = 0;
    DIR *dp = NULL;
    char** tokens;
    struct dirent *ep = NULL;
    
    int rc;
    
    printf("ffirst:search attributes = %x\n",piexchangebyte(SENDNEXT));
    
    memset(msxpath,0,255);
    
    // receive path to list
    rc = secrecvdata(msxpath);
    
    msxpath = replace(msxpath,'\\','/');
    printf("ffirst:curpath=%s msxpath=%s\n",curpath,msxpath);
    
    if (strstr(msxpath,"/*.*")!=NULL) {
        tokens = str_split(msxpath,'*');
        strcpy(msxpath,*(tokens));
        free(tokens);
    }
    
    if (*(msxpath+strlen(msxpath)-1)=='/') {
        *(msxpath+strlen(msxpath)-1) = 0;
    }
    
    printf("ffirst:Exiting curpath=%s,msxpath=%s,rc=%x\n",curpath,msxpath,rc);
    return rc;
    
}

int dos_fnext(char *msxpath,int nfs_findex,int nfs_count,char *filelist) {
    int rc;
    char *thisFile;
    
    printf("fnext:starting\n");
    
    printf("fnext:dirfiles=%s\n",filelist);
    
    if (nfs_count==0) {
        piexchangebyte(__NOFIL);
        printf("fnext:no such file or directory\n");
        return RC_FILENOTFOUND;
    }
    
    if (nfs_count==nfs_findex) {
        piexchangebyte(__NOFIL);
        printf("fnext:end of files\n");
        return RC_SUCCESS;
    }
    
    printf("fnext:file %i of %i:%s\n",nfs_findex,nfs_count,filelist);
    
    thisFile = malloc(255*sizeof(*thisFile));
    thisFile = nfs_setfname(msxpath,filelist);
    printf("fnext:sending:>%s, len=%i<\n",thisFile,strlen(thisFile));
    
    
    piexchangebyte(__SUCCESS);
    
    rc = secsenddata(thisFile+1,24);
    
    printf("fnext:exiting rc = %x\n",rc);
    //free(thisFile);
    
    return rc;
    
}

int pdate() {
    
    if (piexchangebyte(RC_WAIT)!=SENDNEXT) {
        printf("pdate:out of sync\n");
        return RC_FAILED;
    }
    
    time_t rawtime;
    time (&rawtime);
    struct tm  *timeinfo = localtime (&rawtime);
    
    char *buf;
    
    // date
    
    if (piexchangebyte(RC_SUCCESS)!=SENDNEXT) {
        printf("pdate:out of sync\n");
        return RC_FAILED;
    }
    
    piexchangebyte(2000+((timeinfo->tm_year)-100)&0xff);
    piexchangebyte(2000+((timeinfo->tm_year)-100)>>8);
    piexchangebyte((timeinfo->tm_mon)+1);
    piexchangebyte(timeinfo->tm_mday);
    
    // time
    piexchangebyte((timeinfo->tm_hour)+TZ);
    piexchangebyte(timeinfo->tm_min);
    piexchangebyte(timeinfo->tm_sec);
    piexchangebyte(0);
    
    buf = malloc(sizeof(*buf) * 7);
    strcpy(buf,"Pi:Ok\n");
    senddatablock(buf,strlen(buf)+1,true);
    free(buf);
    
    return RC_SUCCESS;
    
}

int pplay(char *msxcommand) {
    int rc;
    char *buf;
    char *fname;
    char** tokens;
    FILE *fp;
    char *msxcommandtmp;
    
    printf("pplay:Starting for command %s\n",msxcommand);
    if (piexchangebyte(RC_WAIT)!=SENDNEXT) {
        printf("pplay:out of sync\n");
        return RC_FAILED;
    }
    
    // new code with shell script taking care of logic
    printf("pplay:Calling media player for %s\n",msxcommand);
    fname = malloc(sizeof(*fname) * 128);
    sprintf(fname,"/home/pi/msxpi/pplay.sh %s>/tmp/msxpi_out.txt 2>&1",msxcommand);
    if(fp = popen(fname, "r")) {
        fclose(fp);
        if (piexchangebyte(RC_SUCCESS)==SENDNEXT) {
            buf = malloc(sizeof(*buf) * 25 );
            strcpy(buf,"ptype /tmp/msxpi_out.txt");
            ptype(buf);
            //free(buf);
        }
        rc = RC_SUCCESS;
    } else {
        piexchangebyte(RC_FAILED);
        rc = RC_FAILNOSTD;
    }

    
    /*
    if (strlen(msxcommand) <= 5) {
        printf("pplay:Missing parameters\n");
        if (piexchangebyte(RC_FAILED)==SENDNEXT) {
            buf = malloc(sizeof(*buf) * 99 );
            strcpy(buf,"Missing parameters\nSyntax:\npplay play|loop|pause|resume|stop|getids|getlids <filename|processid>");
            senddatablock(buf,strlen(buf)+1,true);
            free(buf);
            return 0;
        }
    }
    
    msxcommandtmp = malloc(sizeof(msxcommand)*strlen(msxcommand)+1);
    strcpy(msxcommandtmp,msxcommand);
    tokens = str_split(msxcommand,' ');
    
    // Send ERROR signal to MSX
    // If it is stil in synch, send error message.
    if ((*(tokens + 1) == NULL) || (*(tokens + 2) == NULL)) {
        if ((strcmp(*(tokens + 1),"GETIDS")==0) || (strcmp(*(tokens + 1),"getids")==0) ||
            (strcmp(*(tokens + 1),"GETLIDS")==0) || (strcmp(*(tokens + 1),"getlids")==0)) {
            printf("pplay: get ids received\n");
        } else {
            printf("pplay:Missing parameters\n");
            if (piexchangebyte(RC_FAILED)==SENDNEXT) {
                buf = malloc(sizeof(*buf) * 99);
                strcpy(buf,"Missing parameters\nSyntax:\npplay play|loop|pause|resume|stop|getids|getlids <filename|processid>");
                senddatablock(buf,strlen(buf)+1,true);
                free(buf);
                free(tokens);
                free(msxcommandtmp);
                return RC_SUCCESS;
            }
        }
    }
    
    if((strcmp(*(tokens + 1),"PLAY")==0) || (strcmp(*(tokens + 1),"play")==0) ||
       (strcmp(*(tokens + 1),"LOOP")==0) || (strcmp(*(tokens + 1),"loop")==0)) {
       printf("pplay:starting new player instance for %s\n",msxcommandtmp);
       fname = malloc(sizeof(*fname) * 128);
        
       sprintf(fname,"/home/pi/msxpi/pplay.sh %s>/tmp/msxpi_out.txt 2>&1",msxcommandtmp);
        
       if(fp = popen(fname, "r")) {
           printf("pplay:Success opening file %s\n",fname);
           fclose(fp);
           if (piexchangebyte(RC_SUCCESS)==SENDNEXT) {
               buf = malloc(sizeof(*buf) * 25 );
               strcpy(buf,"ptype /tmp/msxpi_out.txt");
               ptype(buf);
               //free(buf);
           }
           rc = RC_SUCCESS;
       } else {
           printf("pplay:Error opening file %s\n",fname);
           if (piexchangebyte(RC_FAILED)==SENDNEXT) {
               buf = malloc(sizeof(*buf) * 22 );
               strcpy(buf,"Pi:Error opening file");
               senddatablock(buf,strlen(buf)+1,true);
               //free(buf);
           }
           rc = RC_FILENOTFOUND;
       }
    } else if((strcmp(*(tokens + 1),"PAUSE")==0) || (strcmp(*(tokens + 1),"pause")==0)) {
           printf("pplay:Pausing audio playback %s\n",*(tokens + 2));
           fname = malloc(sizeof(*fname) * 128);
           sprintf(fname,"/home/pi/msxpi/pplay.sh dummy PAUSE %s>/tmp/msxpi_out.txt 2>&1",*(tokens + 2));
           if(fp = popen(fname, "r")) {
               fclose(fp);
               if (piexchangebyte(RC_SUCCESS)==SENDNEXT) {
                   buf = malloc(sizeof(*buf) * 25 );
                   strcpy(buf,"ptype /tmp/msxpi_out.txt");
                   ptype(buf);
                   //free(buf);
               }
               rc = RC_SUCCESS;
           } else {
               piexchangebyte(RC_FAILED);
               rc = RC_FAILNOSTD;
           }
    } else if((strcmp(*(tokens + 1),"RESUME")==0) || (strcmp(*(tokens + 1),"resume")==0)) {
            printf("pplay:Resuming audio playback %s\n",*(tokens + 2));
            fname = malloc(sizeof(*fname) * 128);
            sprintf(fname,"/home/pi/msxpi/pplay.sh dummy RESUME %s>/tmp/msxpi_out.txt 2>&1",*(tokens + 2));
            if(fp = popen(fname, "r")) {
                fclose(fp);
                if (piexchangebyte(RC_SUCCESS)==SENDNEXT) {
                    buf = malloc(sizeof(*buf) * 25 );
                    strcpy(buf,"ptype /tmp/msxpi_out.txt");
                    ptype(buf);
                    //free(buf);
                }
                rc = RC_SUCCESS;
            } else {
                piexchangebyte(RC_FAILNOSTD);
                rc = RC_FAILED;
            }
    } else if((strcmp(*(tokens + 1),"STOP")==0) || (strcmp(*(tokens + 1),"stop")==0)) {
            printf("pplay:Stopping audio playback %s\n",*(tokens + 2));
            fname = malloc(sizeof(*fname) * 128);
            sprintf(fname,"/home/pi/msxpi/pplay.sh dummy STOP %s>/tmp/msxpi_out.txt 2>&1",*(tokens + 2));
            if(fp = popen(fname, "r")) {
                fclose(fp);
                if (piexchangebyte(RC_SUCCESS)==SENDNEXT) {
                    buf = malloc(sizeof(*buf) * 25 );
                    strcpy(buf,"ptype /tmp/msxpi_out.txt");
                    ptype(buf);
                    //free(buf);
                }
                rc = RC_SUCCESS;
            } else {
                piexchangebyte(RC_FAILED);
                rc = RC_FAILNOSTD;
            }
    } else if((strcmp(*(tokens + 1),"GETIDS")==0) || (strcmp(*(tokens + 1),"getids")==0)) {
        printf("pplay:Getting audio id\n");
        fname = malloc(sizeof(*fname) * 128);
        sprintf(fname,"/home/pi/msxpi/pplay.sh dummy GETIDS>/tmp/msxpi_out.txt 2>&1");
        if(fp = popen(fname, "r")) {
            fclose(fp);
            if (piexchangebyte(RC_SUCCESS)==SENDNEXT) {
                buf = malloc(sizeof(*buf) * 25 );
                strcpy(buf,"ptype /tmp/msxpi_out.txt");
                ptype(buf);
                //free(buf);
            }
        } else {
            piexchangebyte(RC_FAILNOSTD);
            rc = RC_FAILED;
        }
    } else if((strcmp(*(tokens + 1),"GETLIDS")==0) || (strcmp(*(tokens + 1),"getlids")==0)) {
        printf("pplay:Getting audio loop id\n");
        fname = malloc(sizeof(*fname) * 128);
        sprintf(fname,"/home/pi/msxpi/pplay.sh dummy GETLIDS>/tmp/msxpi_out.txt 2>&1");
        if(fp = popen(fname, "r")) {
            fclose(fp);
            if (piexchangebyte(RC_SUCCESS)==SENDNEXT) {
                buf = malloc(sizeof(*buf) * 25 );
                strcpy(buf,"ptype /tmp/msxpi_out.txt");
                ptype(buf);
                //free(buf);
            }
        } else {
            piexchangebyte(RC_FAILNOSTD);
            rc = RC_FAILED;
        }
    } else {
        if (piexchangebyte(RC_FAILED)==SENDNEXT) {
            buf = malloc(sizeof(*buf) * 75 );
            strcpy(buf,"Invalid parameters\nSyntax:\npplay play|loop|pause|resume|stop|getids|getlids <filename|processid>");
            senddatablock(buf,strlen(buf)+1,true);
            //free(buf);
        }
        free(tokens);
        return 0;
    }
    
    */
    
    printf("pplay:exiting rc = %x\n",rc);

    
    //free(msxcommandtmp);
    free(fname);
    //free(tokens);
    
    return rc;
}

int main(int argc, char *argv[]){
    
    int startaddress,endaddress,execaddress;
    int pcopystat2 = 0;
    
    // numdrives is hardocde here to assure MSX will always have only 2 drives allocated
    // more than 2 drives causes some MSX to hang
    char numdrives = 0;
    
    unsigned char appstate = st_init;
    
    unsigned char mymsxbyte;
    unsigned char mymsxbyte2;
    
    int rc;
    
    struct psettype psetvar[10];
    strcpy(psetvar[0].var,"PATH");strcpy(psetvar[0].value,"/home/pi/msxpi");
    strcpy(psetvar[1].var,"DRIVE0");strcpy(psetvar[1].value,"disks/msxpiboot.dsk");
    strcpy(psetvar[2].var,"DRIVE1");strcpy(psetvar[2].value,"disks/msxpitools.dsk");
    strcpy(psetvar[3].var,"WIDTH");strcpy(psetvar[3].value,"80");
    strcpy(psetvar[4].var,"free");strcpy(psetvar[4].value,"notused");
    strcpy(psetvar[5].var,"WIFISSID");strcpy(psetvar[5].value,"my wifi");
    strcpy(psetvar[6].var,"WIFIPWD");strcpy(psetvar[6].value,"secret");
    strcpy(psetvar[7].var,"DSKTMPL");strcpy(psetvar[7].value,"disks/msxpi_720KB_template.dsk");
    strcpy(psetvar[8].var,"free");strcpy(psetvar[8].value,"");
    strcpy(psetvar[9].var,"free");strcpy(psetvar[9].value,"");
    
    //pcopy
    int pcopyindex,retries,pcopystat;
    MemoryStruct chunk;
    MemoryStruct *chunkptr = &chunk;
    
    //time_t start_t, end_t;
    
    transferStruct dataInfo;
    struct DiskImgInfo drive0,drive1,currentdrive;
    DOS_SectorStruct sectorInfo;
    
    char buf[255];
    
    // NFS VARIABLES
    int nfs_findex,nfs_fcount;
    char curpath[254];
    char nfs_workingdir[254];
    char nfs_msxpath[65];
    struct dirent *dirfiles;

    // bug in code is oversriting ENV vars below.
    // as a temp workaround I reserved some space here to allow dir entries
    //char dummy[2500];
    
    // there is a memory corruption / leak somewhere in the code
    // if these two variables are moved to other places, and dummy is removed,
    // some commands will crash. PCOPY won't work for sure.
    char msxcommand[255];
    char dummy[250];
    
    if (gpioInitialise() < 0)
    {
        fprintf(stderr, "pigpio initialisation failed\n");
        return 1;
    }
    
    init_spi_bitbang();
    gpioWrite(rdy,LOW);
    
    printf("GPIO Initialized\n");
    printf("Starting MSXPi Server Version %s Build %s\n",version,build);
    
    strcpy(drive0.dskname,psetvar[1].value);
    drive0.deviceNumber = 0;
    msxdos_inihrd(&drive0);
    
    strcpy(drive1.dskname,psetvar[2].value);
    drive1.deviceNumber = 1;
    msxdos_inihrd(&drive1);
    
    while(appstate != st_shutdown){
        
        switch (appstate) {
            case st_init:
                printf("Entered init state. Syncying with MSX...\n");
                appstate = st_cmd;
                pcopystat = 0;
                
                /*if(sync_client()==READY) {
                 printf("ok, synced. Listening for commands now.\n");
                 appstate = st_cmd;
                 } else {
                 printf("OPS...not synced. Will continue trying.\n");
                 appstate = st_init;
                 }*/
                break;
                
            case st_cmd:
                
                printf("st_recvcmd: waiting command\n");
                
                CHECKTIMEOUT = false;
                dataInfo = recvdatablock(msxcommand);
                CHECKTIMEOUT = true;
                
                if(dataInfo.rc==RC_SUCCESS) {
                    //printf("st_recvcmd: received command: ");
                    *(msxcommand + dataInfo.datasize) = '\0';
                    //printf("%s\n",msxcommand);
                    appstate = st_runcmd;
                } else {
                    printf("st_recvcmd: error receiving data\n");
                    appstate = st_cmd;
                }
                break;
                
            case st_runcmd:
                printf("st_run_cmd: running command ");
                
                if(strcmp(msxcommand,"SCT")==0) {
                    printf("DOS_SECINFO\n");
                    
                    if(msxdos_secinfo(&sectorInfo)!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strcmp(msxcommand,"RDS")==0) || (strcmp(msxcommand,"WRS")==0)) {
                    
                    if (sectorInfo.deviceNumber==0)
                        if(strcmp(msxcommand,"RDS")==0) {
                            printf("READ SECTOR\n");
                            // This function could be implemented in this single line,
                            // but I am usign a function instead for learning purposes.
                            //rc = secsenddata(currentdrive+(sectorInfo.initialSector*512),sectorInfo.sectors*512);
                            rc = msxdos_readsector(drive0.data,&sectorInfo);
                        } else {
                            printf("WRITE SECTOR\n");
                            rc = msxdos_writesector(drive0.data,&sectorInfo);
                        }
                        else if (sectorInfo.deviceNumber==1)
                            if(strcmp(msxcommand,"RDS")==0) {
                                printf("READ SECTOR\n");
                                // This function could be implemented in this single line,
                                // but I am usign a function instead for learning purposes.
                                //rc = secsenddata(currentdrive+(sectorInfo.initialSector*512),sectorInfo.sectors*512);
                                rc = msxdos_readsector(drive1.data,&sectorInfo);
                            } else {
                                printf("WRITE SECTOR\n");
                                rc = msxdos_writesector(drive1.data,&sectorInfo);
                            }
                            else {
                                printf("Error. Invalid device number.\n");
                                piexchangebyte(ABORT);
                                break;
                            }
                    
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if(strcmp(msxcommand,"INIHRD")==0) {
                    printf("DOS_INIHRD\n");
                    // limit number of drives to two.
                    if(numdrives<2)
                        numdrives++;
                    appstate = st_cmd;
                    break;
                    
                } else if(strcmp(msxcommand,"DRIVES")==0) {
                    printf("DOS_DRIVES\n");
                    
                    printf("Returning number of drives:%i\n",numdrives);
                    piexchangebyte(numdrives);
                    numdrives = 0;
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"ptype",4)==0) ||
                          (strncmp(msxcommand,"PTYPE",4)==0)) {
                    
                    printf("PTYPE\n");
                    
                    piexchangebyte(SENDNEXT);
                    if (ptype(msxcommand)!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"ploadrom",8)==0) ||
                          (strncmp(msxcommand,"PLOADROM",8)==0)) {
                    
                    printf("PLOADROM\n");
                    rc = ploadrom(&psetvar,msxcommand);
                    
                    appstate = st_cmd;
                    
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!");
                    
                    break;
                    
                } else if((strncmp(msxcommand,"ploadbin",8)==0) ||
                          (strncmp(msxcommand,"loadbin",7)==0) ||
                          (strncmp(msxcommand,"PLOADBIN",8)==0)) {
                    
                    printf("PLOADBIN\n");
                    rc = loadbin(msxcommand);
                    
                    appstate = st_cmd;
                    
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!");
                    
                    break;
                    
                } else if(strcmp(msxcommand,"FMT")==0) {
                    printf("FMT\n");
                    
                    // Read Choice, but not used by the driver
                    mymsxbyte = piexchangebyte(SENDNEXT);
                    printf("st_run_cmd:Choice is %x\n",mymsxbyte);
                    
                    // Read drive number
                    mymsxbyte2 = piexchangebyte(SENDNEXT);
                    printf("st_run_cmd:drive number is %x\n",mymsxbyte2);
                    
                    if (mymsxbyte2 == 0) {
                        rc = msxdos_format(&drive0);
                    } else {
                        rc = msxdos_format(&drive1);
                    }
                    
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"SYN",3)==0) ||
                          (strncmp(msxcommand,"chkpiconn",9)==0) ||
                          (strncmp(msxcommand,"CHKPICONN",9)==0)) {
                    
                    printf("chkpiconn\n");
                    //strcpy(buf,"MSXPi Server is running");
                    
                    //dataInfo = senddatablock(buf,strlen(buf)+1,true);
                    piexchangebyte(READY);
                    
                    //if(dataInfo.rc != RC_SUCCESS)
                    //    printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                
                } else if(strncmp(msxcommand,"RUN STOP",8)==0) {
                    printf("Stopping msxpi-server\n");
                    
                    appstate = st_shutdown;
                    break;
                    
                } else if((strncmp(msxcommand,"#",1)==0) ||
                          (strncmp(msxcommand,"PRUN",4)==0) ||
                          (strncmp(msxcommand,"prun",4)==0)){
                    printf("PRUN\n");
                    
                    if (strncmp(msxcommand,"#",1)==0)
                        memcpy(msxcommand," ",1);
                    else
                        memcpy(msxcommand,"    ",4);
                    
                    if (runpicmd(msxcommand)!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"PDIR",4)==0) ||
                          (strncmp(msxcommand,"pdir",4)==0)) {
                    
                    printf("PDIR\n");
                    
                    if (pdir(&psetvar,msxcommand)!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"PCOPY",5)==0) ||
                          (strncmp(msxcommand,"PCOPY",5)==0)) {
                    printf("pcopystat:%i\n",pcopystat);
                    printf("pcopyindex:%i\n",pcopyindex);
                    printf("pcopyretries:%i\n",retries);
                    
                    printf("PCOPY:");
                    if (pcopystat2==0) {
                        printf("1ST CALL\n");
                        pcopystat2 = 1;
                        pcopyindex = 0;
                        retries = 0;
                        chunk.memory = malloc(1);
                        chunk.size = 0;

                        if (pcopy(&psetvar,msxcommand,chunkptr)!=RC_SUCCESS) {
                            pcopystat2 = 0;
                            printf("!!!!! Error !!!!!\n");
                        } else
                            printf("file size:%i\n",chunk.size);
                    } else {
                        printf("CALLS: %i\n",pcopyindex);
                        rc = uploaddata(chunk.memory,chunk.size,pcopyindex);
                        if (rc==ENDTRANSFER) {
                            printf("ENDTRANSFER\n");

                            pcopystat2 = 0;
                            free(chunk.memory );
    
                            strcpy(buf,"Pi:Ok\n");
                            senddatablock(buf,strlen(buf)+1,true);
                            
                        } else if (rc==RC_SUCCESS) {
                            pcopyindex++;
                        } else if (rc==RC_CRCERROR && retries < GLOBALRETRIES) {
                            retries++;
                        } else {
                            printf("!!!!! Error !!!!!\n");
                            pcopystat2 = 0;
                            free(chunk.memory);
                        }
                    }
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"PSETDISK",8)==0) ||
                          (strncmp(msxcommand,"psetdisk",8)==0)) {
                    
                    printf("PSETDISK\n");
                    
                    currentdrive = psetdisk(msxcommand);
                    if (currentdrive.rc!=RC_FAILED) {
                        if (currentdrive.deviceNumber == 0) {
                            munmap(drive0.data,drive0.size);
                            strcpy(&drive0.dskname,&currentdrive.dskname);
                            printf("calling INIHRD with %s\n",drive0.dskname);
                            msxdos_inihrd(&drive0);
                            strcpy(psetvar[1].value,drive0.dskname);
                        } else if (currentdrive.deviceNumber == 1) {
                            munmap(drive1.data,drive1.size);
                            strcpy(&drive1.dskname,&currentdrive.dskname);
                            printf("calling INIHRD with %s\n",drive1.dskname);
                            msxdos_inihrd(&drive1);
                            strcpy(psetvar[2].value,drive1.dskname);
                        }
                    }
                    
                    if (currentdrive.rc==RC_FAILED)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"PSET",3)==0)  ||
                          (strncmp(msxcommand,"pset",3)==0)) {
                    
                    printf("PSET\n");
                    
                    if (pset(&psetvar,msxcommand)!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"PCD",3)==0)  ||
                          (strncmp(msxcommand,"pcd",3)==0)) {
                    
                    printf("PCD\n");
                    
                    if (pcd(&psetvar,msxcommand)!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"PNEWDISK",8)==0)  ||
                          (strncmp(msxcommand,"pnewdisk",8)==0)) {
                    
                    printf("PNEWDISK\n");
                    
                    if (pnewdisk(msxcommand,psetvar[7].value)!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if((strncmp(msxcommand,"PWIFI",5)==0)  ||
                          (strncmp(msxcommand,"pwifi",6)==0)) {
                    
                    printf("PWIFI\n");
                    
                    if (pwifi(msxcommand,psetvar[5].value,psetvar[6].value)!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
               
                } else if(strncmp(msxcommand,"FFIRST",6)==0) {
                    printf("NFS_FFIRST\n");
                    
                    nfs_findex = 0;
                    printf("NFS_FFIRST:1:curpath=%s,nfs_workingdir=%s\n",curpath,nfs_workingdir);
                    // read msx path or file name
                    dos_ffirst(&curpath,&nfs_workingdir);
                    printf("NFS_FFIRST:2:curpath=%s,nfs_workingdir=%s\n",curpath,nfs_workingdir);
                    
                    // list file(s)
                    if (get_dirent_dir(nfs_workingdir, &dirfiles, &nfs_fcount) == 0) {
                        if (nfs_fcount>1)
                            qsort(dirfiles, nfs_fcount, sizeof *dirfiles, &cmp_dirent);
                        
                        dos_fnext(nfs_workingdir,nfs_findex,nfs_fcount,dirfiles[nfs_findex].d_name);
                        
                    } else
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if(strncmp(msxcommand,"FNEXT",5)==0) {
                    printf("NFS_FNEXT\n");
                    nfs_findex++;
                    printf("NFS_FNEXT:1:nfs_workingdir=%s\n",nfs_workingdir);
                    //printf("NFS_FNEXT:dirfiles=%s\n",dirfiles[nfs_findex]);
                    
                    if (dos_fnext(nfs_workingdir,nfs_findex,nfs_fcount,dirfiles[nfs_findex].d_name)!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if(strncmp(msxcommand,"CHDIR",5)==0) {
                    printf("NFS_CHDIR\n");
                    
                    memset(buf,0,255);
                    rc = secrecvdata(buf);
                    
                    printf("NFS_CHDIR:received buf = %s\n",buf);
                    if (rc == RC_SUCCESS) {
                        strcpy(msxcommand,"cd ");
                        strcat(msxcommand,buf);
                        rc = pcd(&psetvar,msxcommand);
                        if (rc==RC_SUCCESS) {
                            strcpy(curpath,psetvar[0].value);
                            piexchangebyte(__SUCCESS);
                        } else
                            piexchangebyte(__DISK);
                    }
                    
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if(strncmp(msxcommand,"GETCD",5)==0) {
                    printf("NFS_GETCD\n");
                    
                    rc = secsenddata(curpath,strlen(curpath)+1);
                    
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if(strncmp(msxcommand,"GETVOL",6)==0) {
                    printf("NFS_GETVOL\n");
                    
                    rc = secsenddata("RaspberryPi",11);
                    
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;
                    
                } else if(strncmp(msxcommand,"PDATE",6)==0) {
                    printf("PDATE\n");
                    
                    rc = pdate();
                    
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;

                } else if(strncmp(msxcommand,"PPLAY",5)==0) {
                    printf("PPLAY\n");
                    
                    rc = pplay(msxcommand);
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!\n");
                    
                    appstate = st_cmd;
                    break;

                } else {
                    printf("st_run_cmd:Command %s - Not Implemented!\n",msxcommand);
                    msxbyte = piexchangebyte(RC_INVALIDCOMMAND);
                    if (msxbyte==SENDNEXT) {
                        strcpy(buf,"Pi:Command not implemented on server");
                        senddatablock(buf,strlen(buf)+1,true);
                    }
                    
                    appstate = st_cmd;
                    break;
                }
                
        }
    }
    
    //create_disk
    /* Stop DMA, release resources */
    printf("Terminating GPIO\n");
    // fprintf(flog,"Terminating GPIO\n");chunkptr
    gpioWrite(rdy,LOW);
    
    //system("/sbin/shutdown now &");
    //system("/usr/sbin/killall msxpi-server &");
    
    
    return 0;
}
