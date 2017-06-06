/*
 ;|===========================================================================|
 ;|                                                                           |
 ;| MSXPi Interface                                                           |
 ;|                                                                           |
 ;| Version : 0.7                                                             |
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
 ; 0.7    : Commands CD and MORE working for http, ftp, nfs, win, local files.
 ; 0.6d   : Added http suport to LOAD and FILES commands
 ; 0.6c   : Initial version commited to git
 ;
 
 PI pinout x GPIO:
 http://abyz.co.uk/rpi/pigpio/index.html
 
 
 Library required by this program and how to install:
 http://abyz.co.uk/rpi/pigpio/download.html
 
 Steps:
 wget abyz.co.uk/rpi/pigpio/pigpio.tar
 tar xf pigpio.tar
 cd PIGPIO
 make -j4
 sudo make install
 
 To compile and run this program:
 cc -Wall -pthread -o msxpi-server msxpi-server.c -lpigpio -lrt

 whenusing curl for http:
 cc -Wall -pthread -o msxpi-server msxpi-server.c -lpigpio -lrt -lcurl
 
 */

#include <stdio.h>
#include <pigpio.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
//#include <curl/curl.h>
#include <assert.h>
#include <time.h>
#include <unistd.h>

#define version "0.7.0.1"

/* GPIO pin numbers used in this program */
#define cs    21
#define sclk  20
#define mosi  16
#define miso  12
#define rdy   25

#define SPI_SCLK_LOW_TIME 1
#define SPI_SCLK_HIGH_TIME 2
#define HIGH 1
#define LOW 0

#define SPI_INT_TIME            1000
#define PIWAITTIMEOUTOTHER      120      // seconds
#define PIWAITTIMEOUTBIOS       60      // seconds

#define st_init                 0       // waiting loop, waiting for a command
#define st_cmd                  1       // trasnfering data for a command
#define st_load_getname         2       // transfering data required by a command
#define st_load_quote           3      // transfering data required by a command
#define st_file_read            4       // transfering data required by a command
#define st_file_send            5       // transfering data required by a command
#define st_send_ack             6
#define st_load_senderr         7       //
#define st_send_rsp             8       //
#define st_recvfname            9
#define st_shutdown             10
#define st_recvparm             11
// #define st_msxpiruncmd       12
#define st_file_wget            13
#define st_set_display          14
#define st_send_text            15
#define st_set_response         16
#define st_send_response        17

#define CMDREAD         0x00
#define LOADROM         0x01
#define LOADCLIENT      0x02
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
#define CMDACK          0xA6
#define PI_READY        0xAA
#define PROCESSING      0xAE
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


int filesize;
int fileindex;
unsigned char appstate = st_init;
unsigned char msxbyte;
unsigned char msxbyterdy;
unsigned char pibyte = NOT_READY;        // initial status is not ready for commands
unsigned char msx_pi_so[65536];
FILE *flog;

//Tools for waiting for a new command
pthread_mutex_t newComMutex = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t newComCond  = PTHREAD_COND_INITIALIZER;

void delay(unsigned int secs) {
    unsigned int retTime = time(0) + secs;   // Get finishing time.
    while (time(0) < retTime);               // Loop until it arrives.
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
    
    result = malloc(sizeof(char*) * count);
    
    if (result)
    {
        size_t idx  = 0;
        char* token = strtok(a_str, delim);
        
        while (token)
        {
            assert(idx < count);
            *(result + idx++) = strdup(token);
            token = strtok(0, delim);
            printf("token,idx,count = %s,%i,%i\n",token,idx,count);
        }
        
        assert(idx == count - 1);
        *(result + idx) = 0;
    }
    
    return result;
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

// This is the function set in the interrupt for the CS signal.
// When CS signal is asserted (by the MSX Interface) to start a transfer,
// RDY signal is asserted LOW (Busy).
// RDY should stay LOW until the current byte is processed by the statre machine.

void func_st_cmd(int gpio, int level, uint32_t tick) {
    if (level == 0) {
        gpioWrite(rdy,LOW);
        if (appstate == st_file_send) {
            //printf("%x = %i\n",fileindex,msx_pi_so[fileindex]);
            msxbyte = SPI_MASTER_transfer_byte(msx_pi_so[fileindex]);
            fileindex++;
        } else if (pibyte == PROCESSING) {
                    SPI_MASTER_transfer_byte(PROCESSING);
                    gpioWrite(rdy,HIGH);
                } else
                    msxbyte = SPI_MASTER_transfer_byte(pibyte);
        
        pthread_mutex_lock(&newComMutex); //Lock to update status
	msxbyterdy = 1;
	pthread_cond_signal(&newComCond); //Signal waiting process
	pthread_mutex_unlock(&newComMutex); //Release.
        
        ///printf("Sent %x, Received %x\n",pibyte,msxbyte);
        
    }
}

int main(int argc, char *argv[])
{
    int startaddress,endaddress,execaddress;
    
    FILE *fp;
    FILE *fdir;
    char** tokens;
    
    struct dirent **fileListTemp;
    unsigned char nextstate,nextbyte,lastcmd,FSTYPE,syncherrorcount,syncherrorcount2;
    char buf_parm[255];
    char msx_path1[255];
    char msx_path2[255];
    char temp_path1[255];
    char temp_path2[255];
    char temp_str[255];

    char remotecommand[255];
    char remoteuser[255];
    char remotepass[255];
    char wifissid[50];
    char wifipass[50];
    char remotetimeout[2] = "20";

    
    int idx, TRANSFTIMEOUT,noOfFiles,i;

    int bootdelaycnt = 10;            //After a boot,Pi will cycle in st_cmd before accepting commands
    char hloadfname[50] = "/tmp/msxpifile1.tmp";
    time_t start_t, end_t;
    double diff_t;

    appstate = st_init;
    
    if (gpioInitialise() < 0)
    {
        fprintf(stderr, "pigpio initialisation failed\n");
        // fprintf(flog, "pigpio initialisation failed\n");
        return 1;
    }
    
    init_spi_bitbang();
    gpioWrite(rdy,LOW);
    
    printf("GPIO Initialized\n");
    // fprintf(flog,"GPIO Initialized\n");
    
    printf("Starting MSXPi Server v%s\n",version);
    // fprintf(flog, "Starting MSXPi Server v%s\n",version);
    
    time(&start_t);
    
    // waiti Pi boot and be ready for commands
    // while (difftime(time(&end_t), start_t) < bootdelaycnt) time(&end_t);
    
    gpioSetISRFunc(cs, FALLING_EDGE, SPI_INT_TIME, func_st_cmd);
    
    while(appstate != st_shutdown){
    //while(1==1){
        switch (appstate) {
            case st_init:
                printf("Entered init state\n");
                // fprintf(flog,"Entered init state\n");
                
                memset(temp_path1,0,255);
                memset(temp_path2,0,255);
                memset(msx_path1,0,255);
                memset(msx_path2,0,255);
                memset(buf_parm,0,255);
                memset(remoteuser,0,sizeof(remoteuser));
                memset(remoteuser,0,sizeof(remotepass));
                syncherrorcount  = 0;
                syncherrorcount2 = 0;
                
                appstate = st_cmd;
                nextstate = st_cmd;
                msxbyterdy = 0;
                msxbyte = 0;
                nextbyte = PI_READY;
                idx = 0;
                gpioWrite(rdy,HIGH);
                break;
                
            case st_cmd:
        
	        pthread_mutex_lock(&newComMutex);
				while (msxbyterdy == 0) {
					fflush(stdout); //Print all the buffered information
					pthread_cond_wait(&newComCond, &newComMutex);
				}
				pthread_mutex_unlock(&newComMutex);
                
                if (msxbyterdy) {
					
                    syncherrorcount2++;
                    if (syncherrorcount2>10) syncherrorcount2 = 0;
                    
                    switch (msxbyte) {
                        case SHUTDOWN:
                            printf("Received command SHUTDOWN 0x%x\n",msxbyte);
                            // fprintf(flog,"Received command SHUTDOWN 0x%x\n",msxbyte);
                            pibyte = msxbyte;
                            appstate = st_send_ack;
                            nextstate = st_shutdown;
                            //nextstate = st_cmd;
                            nextbyte = appstate;
                            gpioWrite(rdy,HIGH);
                            break;
                            
                        case LOADCLIENT:
                            printf("Received command LOADCLIENT 0x%x\n",msxbyte);
                            // fprintf(flog,"Received command LOADCLIENT 0x%x\n",msxbyte);
                            //memset(temp_path1,0, sizeof(temp_path1));
                            //temp_path1[0] = '\0';
                            strcpy(buf_parm, "/home/pi/msxpi/msxpi-client.bin");
                            FSTYPE=FSLOCAL;
                            //curr_parm = 0;
                            msxbyterdy = 0;
                            pibyte = NOT_READY;
                            nextstate = msxbyte;
                            appstate = st_file_read;
                            nextstate = st_file_send;
                            lastcmd = LOADCLIENT;
                            gpioWrite(rdy,LOW);
                            break;
                            
                        case LOADROM:
                            printf("Received command LOADROM 0x%x\n",msxbyte);
                            // fprintf(flog,"Received command LOADROM 0x%x\n",msxbyte);
                            //memset(temp_path1,0,sizeof(temp_path1));
                            strcpy(buf_parm,"/home/pi/msxpi/msxpi-rom.bin");
                            FSTYPE=FSLOCAL;
                            //curr_parm = 0;
                            msxbyterdy = 0;
                            pibyte = NOT_READY;
                            nextbyte = msxbyte;
                            appstate = st_file_read;
                            nextstate = st_file_send;
                            lastcmd = LOADROM;
                            gpioWrite(rdy,LOW);
                            break;
                            
                        case CMDLDFILE:
                            printf("CMDLDFILE:Received command CMDLDFILE 0x%x\n",msxbyte);
                            printf("parameter is: %s\n",buf_parm);
                            printf("remotecommand: %s\n",remotecommand);
                            
                            // enable interrupts, so Pi send NOT_READY messages to MSX
                            
                            pibyte = PROCESSING;
                            //msxbyterdy = 0;
                            gpioWrite(rdy,HIGH);
                            
                            if ((strncmp(buf_parm,"http:",5)!=0) &&
                                (strncmp(buf_parm,"win:",4)!=0) &&
                                (strncmp(buf_parm,"nfs:",4)!=0) &&
                                (strncmp(buf_parm,"ftp:",4)!=0) &&
                                (strncmp(buf_parm,"/",1)!=0)) {
                                strcpy(temp_str,buf_parm);
                                strcpy(buf_parm,msx_path1);
                                strcat(buf_parm,temp_str);
                            }
                                
                            appstate = st_file_read;
                            nextstate = st_file_send;
                            nextbyte = msxbyte;
                            lastcmd = CMDLDFILE;
                            break;
                        
                        case CMDSETVAR:
                        case CMDSETPARM:
                        case CMDSETPATH:          // set parameters
                            lastcmd = msxbyte;
                            printf("Received command CMDSETPARM 0x%x\n",msxbyte);
                            buf_parm[0] = '\0';
                            idx=0;
                            msxbyterdy = 0;
                            pibyte = msxbyte;
                            nextbyte = NOT_READY;
                            appstate = st_send_ack;
                            nextstate = st_recvparm;
                            gpioWrite(rdy,HIGH);
                            
                            break;
                            
                        case CMDDIR:
                            printf("Received command CMDDIR 0x%x\n",msxbyte);
                            // fprintf(flog,"Received command CMDDIR 0x%x\n",msxbyte);
                            
                            // enable interrupts, so Pi send NOT_READY messages to MSX
                            msxbyterdy = 0;
                            pibyte = PROCESSING;
                            gpioWrite(rdy,HIGH);
                            
                            printf("CMDDIR: msx_path1 path is %s\n",msx_path1);
                            printf("CMDDIR: buf_parm  is %s\n",buf_parm);
                        
                            strcpy(temp_path1,msx_path1);
                            
                            if (buf_parm[0]!=0)
                                strcat(temp_path1,buf_parm);    // append command parameter
                            
                            if (temp_path1[0]==0)
                                strcpy(temp_path1,"./");    // append command parameter
                            
                            strcpy(buf_parm,temp_path1);
                            
                            // is this a http/ftp command?
                            //if ((FSTYPE==FSHTTP) || (FSTYPE==FSFTP) || (FSTYPE==FSNFS) || (FSTYPE==FSWIN)) {
                            if ((strncmp(buf_parm,"http:",5)==0) ||
                                (strncmp(buf_parm,"win:",4)==0) ||
                                (strncmp(buf_parm,"nfs:",4)==0) ||
                                (strncmp(buf_parm,"ftp:",4)==0)) {
                                
                                strcpy(temp_path1,remotecommand);
                                strcat(temp_path1,buf_parm);   // append basepath
                                
                                if ((temp_path1[strlen(temp_path1)-1])!=0x2f)
                                    strcat(temp_path1,"/");
                                
                                printf("CMDDIR: 1.acessing %s\n",temp_path1);

                                system(temp_path1);
                                
                                strcpy(temp_path1, "/bin/cat ");
                                strcat(temp_path1, hloadfname);
                                
                                if (FSTYPE==FSHTTP||FSTYPE==FSFTP)
                                    strcat(temp_path1, " | /usr/bin/html2text -width 37 > /tmp/msxpi.tmp");
                                else
                                    strcat(temp_path1, " | /usr/bin/awk '{print $1,$6,$7,$8,$9}' > /tmp/msxpi.tmp");
                            
                                printf("CMDDIR: 2.displaying %s\n",temp_path1);
                                
                                system(temp_path1);
                                
                            } else {

                                printf("CMDDIR %s\n",buf_parm);
                                
                                // fprintf(flog,"Reading dir and writing to temporary file\n");
                                fdir = fopen("/tmp/msxpi.tmp", "w+");
                            
                                noOfFiles = scandir(buf_parm, &fileListTemp, NULL, alphasort);
                                fprintf(fdir,"total: %d files\n",noOfFiles);
                            
                                for(i = 0; i < noOfFiles; i++){
                                    fprintf(fdir, "%s\n",fileListTemp[i]->d_name);
                                }
                                i = 0;
                                fwrite(&i,sizeof(int),1,fdir);
                                fclose(fdir);
                                
                            }
                        
                            printf("CMDDIR: final path is %s\n",buf_parm);
                            printf("CMDDIR: FSTYPE = %i\n",FSTYPE);
                        
                        
                            //memset(buf_parm,0,sizeof(buf_parm));
                            buf_parm[0] = '\0';
                            temp_path1[0] = '\0';
                            
                            // fprintf(flog,"Buffering list of files\n");
                            fp = fopen("/tmp/msxpi.tmp","rb");
                            fseek(fp, 0L, SEEK_END);
                            filesize = ftell(fp) - 3;        // file has 4 zeros at the end, we only need one
                            rewind(fp);
                            fread(msx_pi_so,filesize,1,fp);
                            fclose(fp);
                        
                            msx_pi_so[filesize] = '\0';
                        
                            fileindex = 0;
                            msxbyterdy = 0;
                            pibyte = msxbyte;
                            nextbyte = DATATRANSF;
                            appstate = st_send_ack;
                            nextstate = st_file_send;
                            lastcmd = CMDDIR;
                            TRANSFTIMEOUT = PIWAITTIMEOUTOTHER;
                            // prepare to check time
                            time(&start_t);
                            //printf("Sent ACK 0x%x\n",pibyte);
                            break;
                            
                        case PI_READY:
                            printf("Received command CHECKPICONN 0x%x\n",msxbyte);
                            // fprintf(flog,"Received command CHECKPICONN 0x%x\n",msxbyte);
                            msxbyterdy = 0;
                            pibyte = msxbyte;
                            appstate = st_send_ack;
                            nextstate = st_cmd;
                            nextbyte = appstate;
                            gpioWrite(rdy,HIGH);
                            break;
                            
                        case CMDGETSTAT:
                            printf("Received command PIAPPSTATE 0x%x\n",msxbyte);
                            // fprintf(flog,"Received command PIAPPSTATE 0x%x\n",msxbyte);
                            msxbyterdy = 0;
                            appstate = st_send_ack;
                            nextstate = st_send_rsp;
                            nextbyte = appstate;
                            pibyte = msxbyte;
                            gpioWrite(rdy,HIGH);
                            break;
                            
                        case CMDRESET:
                            printf("Received command RESET 0x%x\n",msxbyte);
                            msxbyterdy = 0;
                            pibyte = msxbyte;
                            appstate = st_send_ack;
                            nextstate = st_init;
                            gpioWrite(rdy,HIGH);
                            break;
                            
                        case CMDREAD:
                            pibyte = PI_READY;
                            printf("Received command READ 0x%x, sent byte 0x%x\n",msxbyte,pibyte);
                            
                            syncherrorcount++;
                            if (syncherrorcount>10 && syncherrorcount==syncherrorcount2) {
                                printf("Out if synch with MSX Client... resetting state\n");
                                // timeout MSX connection
                                delay(5);
                                syncherrorcount  = 0;
                                syncherrorcount2 = 0;
                                printf("Back in st_cmd state... waiting MSX commands.\n");
                            }
                            
                            msxbyterdy = 0;
                            appstate = st_cmd;
                            gpioWrite(rdy,HIGH);
                            break;
                        
                        case CMDPWD:
                            printf("Received command PWD 0x%x\n",msxbyte);
                            
                            if (msx_path1[0]==0)
                                strcpy(msx_path1,"./");

                            // memset(msx_pi_so,0,sizeof(msx_path1));
                            strcpy(msx_pi_so,msx_path1);
                            fileindex = 0;
                            filesize = strlen(msx_path1);
                            pibyte = msxbyte;
                            appstate = st_send_ack;
                            nextstate = st_file_send;
                            msxbyterdy = 0;
                            
                            printf("Current path is %s\n",msx_path1);
                            
                            TRANSFTIMEOUT = PIWAITTIMEOUTOTHER;
                            // prepare to check time
                            time(&start_t);
                            
                            gpioWrite(rdy,HIGH);
                            break;
                            
                        case RUNPICMD:
                            printf("Received command RUNPICMD 0x%x\n",msxbyte);
                            // fprintf(flog,"Received command RUNPICMD 0x%x\n",msxbyte);
                            
		            msxbyterdy = 0;
                            pibyte = PROCESSING;
                            gpioWrite(rdy,HIGH);

                            if(!(fp = popen(buf_parm, "r")))
                            {
                                printf("Command Error.\n");
                                strcpy(temp_str,"Command Error.\n");
                                appstate = st_set_response;
                                msxbyte = CMDERROR;
                                break;
                            }
                            
                            memset(msx_pi_so,0,sizeof(msx_pi_so));
                            fread(msx_pi_so, sizeof(char), sizeof(char) * sizeof(msx_pi_so), fp);
                            
                            fclose(fp);
                            buf_parm[0] = '\0';
                            
                            printf("Command : %s\n",buf_parm);
                            printf("PATH: %s\n",msx_path1);
                            
                            fileindex = 0;
                            filesize = strlen(msx_pi_so);
                            
                            appstate = st_send_ack;
                            nextstate = st_file_send;
                            lastcmd = RUNPICMD;
                            TRANSFTIMEOUT = PIWAITTIMEOUTOTHER;
                            // prepare to check time
                            time(&start_t);
                            
                            msxbyterdy = 0;
                            pibyte = msxbyte;
                            nextbyte = DATATRANSF;
                            
                            gpioWrite(rdy,HIGH);
                            break;
                            
                        case CMDMORE:
                            printf("Received command MORE 0x%x\n",msxbyte);
                            
                            // enable interrupts, for Pi to send PROCESSING messages to MSX
                            msxbyterdy = 0;
                            pibyte = PROCESSING;
                            gpioWrite(rdy,HIGH);
                            
                            printf("CMDMORE: msx_path1 path is %s\n",msx_path1);
                            printf("CMDMORE: buf_parm  is %s\n",buf_parm);
                            
                            strcpy(temp_path1,msx_path1);
                            
                            if (buf_parm[0]!=0)
                                strcat(temp_path1,buf_parm);    // append command parameter
                            
                            if (temp_path1[0]==0)
                                strcpy(temp_path1,"./");    // append command parameter
                            
                            strcpy(buf_parm,temp_path1);
                            
                            printf("CMDMORE: final path is %s\n",buf_parm);
                            printf("CMDMORE: remotecommand is %s\n",remotecommand);
                            
                            // is this a http/ftp command?
                            if ((strncmp(buf_parm,"http:",5)==0) ||
                                (strncmp(buf_parm,"win:",4)==0) ||
                                (strncmp(buf_parm,"nfs:",4)==0) ||
                                (strncmp(buf_parm,"ftp:",4)==0)) {
                                
                                strcpy(temp_path1,remotecommand);
                                strcat(temp_path1,buf_parm);   // append basepath
                                
                                printf("CMDMORE: 1.acessing %s\n",temp_path1);
                                
                                system(temp_path1);
                                
                                strcpy(temp_path1, "/bin/cat ");
                                strcat(temp_path1, hloadfname);
                                strcat(temp_path1," > /tmp/msxpi.tmp");
                                
                                system(temp_path1);
                                
                            } else {
                                strcpy(temp_path1,"/bin/cat ");
                                strcat(temp_path1, buf_parm);
                                strcat(temp_path1," > /tmp/msxpi.tmp");
                                
                                system(temp_path1);
                            }
                            
                            buf_parm[0] = '\0';
                            
                            // fprintf(flog,"Buffering list of files\n");
                            fp = fopen("/tmp/msxpi.tmp","rb");
                            fseek(fp, 0L, SEEK_END);
                            filesize = ftell(fp);
                            rewind(fp);
                            fread(msx_pi_so,filesize,1,fp);
                            fclose(fp);
                            
                            fileindex = 0;
                            msxbyterdy = 0;
                            pibyte = msxbyte;
                            nextbyte = DATATRANSF;
                            appstate = st_send_ack;
                            nextstate = st_file_send;
                            lastcmd = CMDMORE;
                            TRANSFTIMEOUT = PIWAITTIMEOUTOTHER;
                            // prepare to check time
                            time(&start_t);
                            //printf("Sent ACK 0x%x\n",pibyte);
                            break;
                        
                        case WIFICFG:
                            // enable interrupts, for Pi to send PROCESSING messages to MSX
                            msxbyterdy = 0;
                            pibyte = PROCESSING;
                            gpioWrite(rdy,HIGH);
                            
                            printf("Received command WIFICFG 0x%x\n",msxbyte);

                            if (strstr(buf_parm,"display")) {
                                system("ifconfig wlan0 >/tmp/msxpi.tmp");
                                system("ifconfig wlan1 >>/tmp/msxpi.tmp");
                                
                                // this is the response
                                // will read msxpitmp file as text and setup everything needed to start transfer to MSX
                                appstate = st_send_response;
                                break;
                                
                            } else {
                                temp_str[0] = '\0';
                                if (strstr(buf_parm,"add"))
                                    fp = fopen("/etc/wpa_supplicant/wpa_supplicant.conf", "a");\
                                else if (strstr(buf_parm,"replace")) {
                                        fp = fopen("/etc/wpa_supplicant/wpa_supplicant.conf", "w+");
                                        strcpy(temp_str,"ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev\n");
                                        strcat(temp_str,"update_config=1\n");
                                } else {
                                        printf("Parameter invalid.\n");
                                        system("echo Parameter invalid >/tmp/msxpi.tmp");
                                        appstate = st_send_response;
                                        msxbyte = CMDERROR;
                                        break;
                                }
                            }
                            
                            // Reached this point, will add new WiFi network, or replace everything with the current essid/passwd.
                            strcat(temp_str,"network={\n");
                            strcat(temp_str,"\tssid=\"");
                            strcat(temp_str,wifissid);
                            strcat(temp_str,"\"\n");
                            strcat(temp_str,"\tpsk=\"");
                            strcat(temp_str,wifipass);
                            strcat(temp_str,"\"\n");
                            strcat(temp_str,"}\n");
                            
                            fprintf(fp,temp_str);
                            fclose(fp);
                            
                            if (strstr(buf_parm,"wlan1"))
                                system("/sbin/ifdown wlan1;/sbin/ifup wlan1;");
                            else system("/sbin/ifdown wlan0;/sbin/ifup wlan0;");
                                
                            system("echo OK>/tmp/msxpi.tmp");
                            buf_parm[0] = '\0';
                            appstate = st_send_response;
                            break;
                            
                        default:
                            msxbyterdy = 0;
                            printf("Received an invalid command: 0x%x\n",msxbyte);
                            printf("    appstate = %i\n",appstate);
                            pibyte = PI_READY;
                            gpioWrite(rdy,HIGH);
                            break;
                    }
                }
               
                break;
                
            case st_send_rsp:
                if (msxbyterdy) {
                    appstate = nextstate;
                    msxbyterdy = 0;
                    pibyte = 0;
                    gpioWrite(rdy,HIGH);
                    break;
                }
                break;
                
            case st_recvparm:
                if (msxbyterdy) {
                    // End of data?
                    
                    if (msxbyte == 0) {
  
                        printf("finished receiving parameter: %i\n",lastcmd);
                        
                        if ((lastcmd==CMDSETPATH) || (lastcmd==CMDSETPARM)) {
                            
                            
                            //printf("last char in buf_parm is position %i\n",buf_parm[idx]);
                            
                            if (lastcmd==CMDSETPATH) {
                                printf("entered  (lastcmd==CMDSETPATH) %s\n",buf_parm);
                                if (buf_parm[idx-1]!=0x2f) {  // "/"
                                    buf_parm[idx] = 0x2f;
                                    idx++;
                                }
                            }
                            
                            buf_parm[idx] = '\0';
                            
                            printf("Parameter received in buf_parm = %s\n",buf_parm);
                            
                            if (strncmp(buf_parm,"win:",4)==0) {
                                strcpy(temp_str,buf_parm);
                                tokens = str_split(temp_str, ':');
                                strcpy(temp_path1,"mkdir -p /tmp/msxpismb; /bin/mount -t cifs ");
                                
                                // is remote credentials set?
                                // if so, append to request
                                if ((remoteuser[0]!=0)&&(remotepass[0]!=0)) {
                                    printf("smb using credentials %s:%s\n",remoteuser,remoteuser);
                                    strcat(temp_path1," -o username=");
                                    strcat(temp_path1,remoteuser);
                                    strcat(temp_path1,",");
                                    strcat(temp_path1,"password=");
                                    strcat(temp_path1,remotepass);
                                    strcat(temp_path1," ");
                                } else
                                    strcat(temp_path1," -o username=guest,password=guest ");
                                
                                strcat(temp_path1,*(tokens + 1));
                                
                                strcat(temp_path1," /tmp/msxpismb;chmod 755 /tmp/msxpismb");
                                
                                printf("%s\n",temp_path1);
                                
                                system(temp_path1);
                                
                                // memset(msx_path1,0,sizeof(msx_path1));
                                strcpy(msx_path1,"/tmp/msxpismb/");
                                chdir(msx_path1);
                                
                                // memset(buf_parm,0,sizeof(buf_parm));
                                buf_parm[0] = '\0';
                                
                                free(tokens);
                                FSTYPE=FSWIN;
                                
                            } else if (strncmp(buf_parm,"nfs:",4)==0) {
                                strcpy(temp_str,buf_parm);
                                tokens = str_split(temp_str, '/');
                                printf("tokens returned %s\n",tokens);
                                // memset(temp_path1,0,sizeof(temp_path1));
                                strcpy(temp_path1,"mkdir -p /tmp/msxpinfs; /bin/mount -o nolock,rw ");
                                strcat(temp_path1,*(tokens + 1));
                                strcat(temp_path1,":/");
                                strcat(temp_path1,*(tokens + 2));
                                
                                i=3;
                                while (*(tokens + i))
                                {
                                    strcat(temp_path1,"/");
                                    strcat(temp_path1,*(tokens + i));
                                    i++;
                                }
                                
                                strcat(temp_path1," /tmp/msxpinfs;chmod 755 /tmp/msxpinfs");
                                
                                printf("%s\n",temp_path1);
                                
                                system(temp_path1);
                                // memset(msx_path1,0,sizeof(msx_path1));
                                strcpy(msx_path1,"/tmp/msxpinfs/");
                                chdir(msx_path1);
                                
                                //memset(buf_parm,0,sizeof(buf_parm));
                                buf_parm[0] = '\0';
                                
                                free(tokens);
                                FSTYPE=FSNFS;

                            } else if (strncmp(buf_parm,"http:",5)==0) {
                                printf("2Parameter received in buf_parm = %s\n",buf_parm);
                                strcpy(temp_str,buf_parm);
                                tokens = str_split(temp_str, ':');
                                printf("after token Parameter received in buf_parm = %s\n",buf_parm);
                                // strcpy(remotecommand,"/usr/bin/curl --connect-timeout ");
                                strcpy(remotecommand,"/usr/bin/wget --timeout=");
                                strcat(remotecommand,remotetimeout);
                                strcat(remotecommand," ");

                                
                                // is remote credentials set?
                                // if so, append to request
                                if ((remoteuser[0]!=0)&&(remotepass[0]!=0)) {
                                    printf("http using credentials %s:%s\n",remoteuser,remoteuser);
                                    strcat(remotecommand," --user=");
                                    strcat(remotecommand,remoteuser);
                                    strcat(remotecommand," --password=");
                                    strcat(remotecommand,remotepass);
                                }
                                
                                // output for curl command
                                strcat(remotecommand," -O ");
                                strcat(remotecommand,hloadfname);
                                strcat(remotecommand," ");
                                
                               if (lastcmd==CMDSETPATH) {
                                    strcpy(msx_path1,"http:");
                                    strcat(msx_path1,*(tokens + 1));
                                    printf("%s %s\n",remotecommand,msx_path1);
                                
                                    if (*(tokens + 2)) {
                                        strcat(msx_path1,":");
                                        strcat(msx_path1,*(tokens + 2));
                                    }
                                    printf("%s %s\n",remotecommand,msx_path1);
                                    buf_parm[0] = '\0';
                                    free(tokens);
                                }
                                
                                printf("exiting http check with buf_parm = %s\n",buf_parm);
                                FSTYPE=FSHTTP;
                                
                            } else if (strncmp(buf_parm,"ftp:",4)==0) {
                                strcpy(temp_str,buf_parm);
                                tokens = str_split(temp_str, ':');
                                strcpy(remotecommand,"/usr/bin/wget --timeout=");
                                strcat(remotecommand,remotetimeout);
                                strcat(remotecommand," ");
                                
                                
                                // is remote credentials set?
                                // if so, append to request
                                if ((remoteuser[0]!=0)&&(remotepass[0]!=0)) {
                                    printf("ftp using credentials %s:%s\n",remoteuser,remoteuser);
                                    strcat(remotecommand," --user=");
                                    strcat(remotecommand,remoteuser);
                                    strcat(remotecommand," --password=");
                                    strcat(remotecommand,remotepass);
                                }
                                
                                // output for curl command
                                strcat(remotecommand," -O ");
                                strcat(remotecommand,hloadfname);
                                strcat(remotecommand," ");
                                
                                if (lastcmd==CMDSETPATH) {
                                    strcpy(msx_path1,"ftp:");
                                    strcat(msx_path1,*(tokens + 1));

                                    //memset(buf_parm,0,sizeof(buf_parm));
                                    buf_parm[0] = '\0';
                                    free(tokens);
                                }
                                
                                printf("%s %s\n",remotecommand,msx_path1);
                                FSTYPE=FSFTP;
                            
                            } else {
                                
                                if (msx_path1[0]==0x2f || buf_parm[0]==0x2f)
                                    FSTYPE = FSLOCAL;
                                
                                printf("entered  (lastcmd==CMDSETPATH:relative path) idx=%i\n",idx);
                                
                                if (lastcmd==CMDSETPATH && (idx==0 || buf_parm[idx-1]!=0x2f)) {  // "/"
                                    buf_parm[idx] = 0x2f;
                                    idx++;
                                }
                                
                                buf_parm[idx] = '\0';
                                
                                printf("preparing path from buf_parm: %s\n",buf_parm);
                                
                                if ((lastcmd==CMDSETPATH)) {
                                    if (buf_parm[0]!=0x2f && buf_parm[0]!=0)
                                        strcat(msx_path1,buf_parm);
                                    else
                                        strcpy(msx_path1,buf_parm);
                                
                                    if (FSTYPE==FSLOCAL)
                                        chdir(msx_path1);
                                    
                                    printf("new path is %s\n",msx_path1);
                                    buf_parm[0] = '\0';
                                } else {
                                    strcpy(msx_path2,msx_path1);
                                    strcat(msx_path2,buf_parm);
                                    
                                    printf("new path is %s\n",msx_path2);
                                }
                                
                            }
                        } else if (lastcmd==CMDSETVAR) {
                            
                                    printf("entered  (lastcmd==CMDSETVAR)\n");
                                    buf_parm[idx] = '\0';
                                    printf("st_recvparm set %s\n",buf_parm);
                                    if (strstr(buf_parm,"display")) {
                                        printf("st_recvparm set display: %s\n",buf_parm);

                                        // enable interrupts, for Pi to send PROCESSING messages to MSX
                                        msxbyterdy = 0;
                                        appstate = st_set_display;
                                        buf_parm[0] = '\0';
                                        break;
                                    } else if (strncmp(buf_parm,"remoteuser=",11)==0) {
                                        
                                        msxbyterdy = 0;
                                        tokens = str_split(buf_parm, '=');
                                        
                                        if (*(tokens + 1))
                                            strcpy(remoteuser,*(tokens+1));
                                        else
                                            remoteuser[0] = '\0';
                                            
                                        printf("strncmp is remoteuser %s\n",*(tokens+1));
                                        
                                        appstate = st_set_display;
                                        break;
                                        
                                    } else if (strncmp(buf_parm,"remotepass=",11)==0) {
                                        msxbyterdy = 0;
                                        tokens = str_split(buf_parm, '=');
                                        
                                        if (*(tokens + 1))
                                            strcpy(remotepass,*(tokens+1));
                                        else
                                            remotepass[0] = '\0';
                                            
                                        appstate = st_set_display;
                                        break;
                                    } else if (strncmp(buf_parm,"wifissid=",9)==0) {
                                        
                                        msxbyterdy = 0;
                                        tokens = str_split(buf_parm, '=');
                                        
                                        if (*(tokens + 1))
                                            strcpy(wifissid,*(tokens+1));
                                        else
                                            wifissid[0] = '\0';
                                        
                                        printf("strncmp is wifissid %s\n",*(tokens+1));
                                        
                                        appstate = st_set_display;
                                        break;
                                        
                                    } else if (strncmp(buf_parm,"wifipass=",9)==0) {
                                        msxbyterdy = 0;
                                        tokens = str_split(buf_parm, '=');
                                        
                                        if (*(tokens + 1))
                                            strcpy(wifipass,*(tokens+1));
                                        else
                                            wifipass[0] = '\0';
                                        
                                        appstate = st_set_display;
                                        break;
                                        
                                    } else {
                                        buf_parm[0] = '\0';
                                        strcpy(msx_pi_so,"Error: Variable does not exist");
                                        appstate = st_send_text;
                                        break;

                                    }
                            
                        // This else covers scenarios such as:
                        // dir <dir>
                        // load <file>, etc... the paramtere <...> will be picked up here.
                        } else if (lastcmd==CMDSETPARM) {
                            printf("entered  (lastcmd==CMDSETPARM)\n");
                            
                            buf_parm[idx] = '\0';
                            
                            printf("Received command with parameter. Final parameter is : %s\n",buf_parm);

                        }
                        
                        // This code is common for CMDSETPARM,CMDSETVAR,CMDSETPATH
                        printf("CMDSET COMMON PATH\n");
                        appstate = st_cmd;
                        pibyte = PI_READY;
                        msxbyterdy = 0;
                        gpioWrite(rdy,HIGH);
                        break;
                    
                    // There is still data to come
                    } else {

                        //printf("st_recvparm: received buf_parm %s\n",buf_parm);
                        printf("reading char for parameter: %c,%i\n",msxbyte,idx);
                        buf_parm[idx] = msxbyte;
                        idx++;
                        pibyte = PI_READY;
                        msxbyterdy = 0;
                        
                        gpioWrite(rdy,HIGH);
                        break;
                    }
                }
                break;
        
            // call this state to send a response / string to msx
            // string to send should be in array temp_str
            case st_set_response:
                printf("st_set_response: writting response to local buffer file\n");
                fp = fopen("/tmp/msxpi.tmp", "w+");
                fprintf(fp,temp_str);
                appstate = st_send_response;
                break;
            
            // call this state to send a response / string to msx
            // string / text must be already in file /tmp/msxpi.tmp
            case st_send_response:
                printf("st_send_response: reading response to local buffer file\n");
                
                buf_parm[0] = '\0';
    
                fp = fopen("/tmp/msxpi.tmp","rb");
                fseek(fp, 0L, SEEK_END);
                filesize = ftell(fp);
                rewind(fp);
                fread(msx_pi_so,filesize,1,fp);
                fclose(fp);
                
                fileindex = 0;
                msxbyterdy = 0;
                pibyte = msxbyte;
                nextbyte = DATATRANSF;
                appstate = st_send_ack;
                nextstate = st_file_send;
                TRANSFTIMEOUT = PIWAITTIMEOUTOTHER;
                // prepare to check time
                time(&start_t);
                //printf("Sent ACK 0x%x\n",pibyte);
                break;
        
            case st_send_text:
        
                fileindex = 0;
                filesize = strlen(msx_pi_so);
                appstate = st_file_send;
                msxbyterdy = 0;
        
                TRANSFTIMEOUT = PIWAITTIMEOUTOTHER;
                // prepare to check time
                time(&start_t);
        
                gpioWrite(rdy,HIGH);
                break;
        
            case st_file_read:
                
                printf("st_file_read: current parameter is %s\n",buf_parm);
                printf("command type is %i\n",FSTYPE);
                
                // is this a http/ftp command?
                if (FSTYPE >= FSHTTP) {
                    
                    strcpy(temp_path1,remotecommand);
                    strcat(temp_path1,buf_parm);   // append basepath

                    printf("st_file_read: acessing %s\n",temp_path1);
                    
                    system(temp_path1);
                    
                    strcpy(buf_parm,hloadfname);
                }
                
                printf("st_file_read: load file %s\n",buf_parm);
                
                fp = fopen(buf_parm,"rb");
                fileindex = 0;
                
                if (fp) {
                    
                    // get file type and size
                    fread(msx_pi_so,7,1,fp);
                    fseek(fp, 0L, SEEK_END);
                    filesize = ftell(fp);
                    rewind(fp);
                    
                    if (msx_pi_so[0] == 0xFE) {
                        printf("File type     = BIN\n");
                        startaddress = msx_pi_so[fileindex+1] + (256 * msx_pi_so[fileindex+2]);
                        endaddress   = msx_pi_so[fileindex+3] + (256 * msx_pi_so[fileindex+4]);
                        execaddress  = msx_pi_so[fileindex+5] + (256 * msx_pi_so[fileindex+6]);
                        //fileType = BIN;
                    } else if (msx_pi_so[0] == 0x41 && msx_pi_so[1] == 0x42) {
                        printf("File type     = ROM\n");
                        startaddress = 0x4000;
                        endaddress   = 0x4000 + filesize - 1;
                        execaddress  = msx_pi_so[fileindex+2] + (256 * msx_pi_so[fileindex+3]);
                        //fileType = ROM;
                    } else {
                        printf("File type     = RAW\n");
                        startaddress=0;
                        endaddress=0;
                        execaddress=0;
                        //fileType = RAW;
                    }
                    
                    // Insert file size in the beggining of the file if not EPROM file
                    if (lastcmd == LOADROM)
                        fread(msx_pi_so,filesize,1,fp);
                    else {
                        msx_pi_so[0] = (int) (filesize % 256);   // LSB
                        msx_pi_so[1] = (int) filesize / 256;     // MSB
                        fread(msx_pi_so+2,filesize,1,fp);
                    }
                    
                    fclose(fp);
                    //memset(temp_path1,0,sizeof(temp_path1));
                    
                    printf("File name     = %s\n",buf_parm);
                    printf("Filesize      = %i\n",filesize);
                    printf("Start address = %x\n",startaddress);
                    printf("End address   = %x\n",endaddress);
                    printf("Exec address  = %x\n",execaddress);
                    
                    buf_parm[0] = '\0';
                    time(&start_t);
                    
                    if (lastcmd == LOADROM || lastcmd == LOADCLIENT) {
                        pibyte = msxbyte;
                        //nextbyte = NOT_READY;
                        appstate = st_file_send;
                        nextstate = st_cmd;
                        TRANSFTIMEOUT = PIWAITTIMEOUTBIOS;
                        gpioWrite(rdy,HIGH);
                        msxbyterdy = 0;
                        break;
                    } else {
                        TRANSFTIMEOUT = PIWAITTIMEOUTOTHER;
                        //nextbyte = msxbyte;
                        nextstate = st_file_send;
                        msxbyterdy = 0;
                        pibyte = msxbyte;
                        appstate = st_send_ack;
                        break;
                    }
   
                } else {
                    printf("Error reading file %s\n",buf_parm);
                    // fprintf(flog,"Error reading file %s\n",buf_parm);
                    msxbyterdy = 0;
                    appstate = st_send_ack;
                    nextstate = st_cmd;
                    pibyte = FNOTFOUND;
                    gpioWrite(rdy,HIGH);
                    break;
                    
                }
                
            case st_send_ack:
                if (msxbyterdy) {
                    printf("st_send_ack: sent 0x%x\n",pibyte);
                    // fprintf(flog,"st_send_ack: sent 0x%x\n",pibyte);
                    msxbyterdy = 0;
                    appstate = nextstate;
                    nextstate = st_cmd;
                    pibyte = nextbyte;
                    gpioWrite(rdy,HIGH);
                    break;
                }
                
                break;
                
            case st_file_send:
                if (msxbyterdy) {
                    if (fileindex+1 > filesize )  {
                        printf("st_file_send: end of file transfer\n");
                        appstate = st_cmd;
                        msxbyterdy = 0;
                        pibyte = 0;
                        //memset(msx_pi_so,0,65536);
                        gpioWrite(rdy,HIGH);
                        break;
                    }
                    msxbyterdy = 0;
                    gpioWrite(rdy,HIGH);
                }
                
                time(&end_t);
                diff_t = difftime(end_t, start_t);
                if (diff_t > TRANSFTIMEOUT) {
                    printf("st_file_send: Waiting timeout. Resseting to init state\n");
                    // fprintf(flog,"st_file_send: Waiting timeout. Resseting to init state\n");
                    appstate = st_cmd;
                    msxbyterdy = 0;
                    gpioWrite(rdy,HIGH);
                    break;
                }
                
                break;
        
            case st_set_display:
                // enable interrupts, for Pi to send PROCESSING messages to MSX
                msxbyterdy = 0;
                pibyte = PROCESSING;
                gpioWrite(rdy,HIGH);

                printf("st_set_display");
                
                msx_pi_so[0] = '\0';
                
                // list here all the variables available for the MSXPi Client
                //-
                strcpy(msx_pi_so,"remoteuser");
                strcat(msx_pi_so,"=");
                strcat(msx_pi_so,remoteuser);
                strcat(msx_pi_so,"\n");
                //-
                strcat(msx_pi_so,"remotepass");
                strcat(msx_pi_so,"=");
                strcat(msx_pi_so,remotepass);
                strcat(msx_pi_so,"\n");
                //-
                strcat(msx_pi_so,"msx_path1");
                strcat(msx_pi_so,"=");
                strcat(msx_pi_so,msx_path1);
                strcat(msx_pi_so,"\n");
                //-
                strcat(msx_pi_so,"wifissid");
                strcat(msx_pi_so,"=");
                strcat(msx_pi_so,wifissid);
                strcat(msx_pi_so,"\n");
                //-
                strcat(msx_pi_so,"wifipass");
                strcat(msx_pi_so,"=");
                strcat(msx_pi_so,wifipass);
                strcat(msx_pi_so,"\n");
                //-
                fileindex = 0;
                filesize = strlen(msx_pi_so);
                appstate = st_file_send;
                msxbyterdy = 0;
                
                TRANSFTIMEOUT = PIWAITTIMEOUTOTHER;
                // prepare to check time
                time(&start_t);
                
                gpioWrite(rdy,HIGH);
                break;
                
        }
    }
    
    /* Stop DMA, release resources */
    printf("Terminating GPIO\n");
    // fprintf(flog,"Terminating GPIO\n");
    gpioWrite(rdy,LOW);
    
    //system("/sbin/shutdown now &");
    //system("/usr/sbin/killall msxpi-server &");
    
    return 0;
}
