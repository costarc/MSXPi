/*
 ;|===========================================================================|
 ;|                                                                           |
 ;| MSXPi Interface                                                           |
 ;|                                                                           |
 ;| Version : 0.8                                                             |
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
 ; 0.1    : Initial version
 */

//Skeleton to create the Server-side code.
// Add your code to msxpi-server.c using the below guidelines as a suggestion

// Under "case st_cmd:" add the filter for your command, and the corresponding
//        call to the function.

                } else if((strncmp(msxcommand,"ploadrom",8)==0) ||
                          (strncmp(msxcommand,"PLOADROM",8)==0)) {
                    
                    printf("PLOADROM\n");
                    rc = loadrom(msxcommand);
                    
                    appstate = st_cmd;
                    
                    if (rc!=RC_SUCCESS)
                        printf("!!!!! Error !!!!!");
                    
                    break;
                    
// Create the function for your command
int loadrom(unsigned char *msxcommand) {
    int rc;
    unsigned char *buf;
    unsigned char *stdout;
    unsigned char mymsxbyte;
    transferStruct dataInfo;
    
    printf("loadrom:starting %s\n",msxcommand);
    // start the program logic here
    // ...

    
    // if the processing should be aborted due to an error
    // send this to MSX.
    // Pre-processing errors may be, as for example:
    //   lcoal file not found
    //   remote server connection failed
    //   parameters invalid
    //   etc...
    
    if (SOME_ERROR_TEST) {
        piexchangebyte(ABORT);
        rc = RC_FILENOTFOUND;  // OR OTHER ERROR CODE
    else {
        // Initial processing worked, so continue.
        // To receive binary data from MSX if required,
        // assuming here you already have a pointer "unsigned char *buf" to store data:
        dataInfo = recvdatablock(buf);rc = dataInfo.rc;
        
        // Receive binary data, with CRC checks (slower)
        rc = secrecvdata(buf);

        // Send binary data to MSX
        dataInfo = senddatablock(buf,size,true);rc = dataInfo.rc;
        
        // Send binary data, with CRC checks (slower)
        rc = secsenddata(buf,size);
        
        // Evaluate results and send status to MSX
        // This assume the error was due to some external condition,
        // and that communication with MSX is working properly and in sync.
        if(rc != RC_SUCCESS) {
            printf("loadrom:Program Failed. Aborting\n");
            rc = RC_UNDEFINED;
            stdout = (unsigned char *)malloc(sizeof(unsigned char) * 28); // length of stdout string below
            strcpy(stdout,"Pi:Program Failed. Aborting");
            piexchangebyte(ABORT);
        } else {
            printf("loadrom:Program completd successfully\n");
            stdout = (unsigned char *)malloc(sizeof(unsigned char) * 33); // length of stdout string below
            strcpy(stdout,"Pi:Program completd successfully");
            piexchangebyte(ENDOFTRANSFER);
        }

        // Send the message (success or fail) to MSX
        printf("loadrom:Sending stdout to MSX: %s\n",stdout);
        dataInfo = senddatablock(stdout,strlen(stdout)+1,true);

        free(stdout);
    }
        
    printf("loadrom:exiting rc = %x\n",rc);
    return rc;
    
}
