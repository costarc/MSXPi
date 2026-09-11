/*
 * MSXPi Interface
 * Version 1.6
 * ------------------------------------------------------------------------------
 * MIT License
 *
 * Copyright (c) 2015-2026 Ronivon Costa
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 * ------------------------------------------------------------------------------
 */

#define  __SDK_MSXVERSION__ 2

#define CMDLINE 0x80

#define NODEBUGMODE
#define NOBIOSDEBUGMODE
#define CONTROL_PORT1		0x56
#define CONTROL_PORT2		0x57
#define DATA_PORT1			0x5A
#define GLOBALRETRIES		1     // adjust as needed
#define MAX_BLOCK_RETRIES	3
#define BLKSIZE				512   // buffer size for data transfer
#define MAXBUFSIZE			8192  // 8 KB buffer size
#define BUFADDRESS			0xC000

#define READY_ACK			0xA0
#define SENDNEXT			0xA1
#define ENDTRANSFER			0xA2
#define READY				0xAA
#define RC_CHKSUM_ERR		0xAD
#define BUSY				0xAE
#define RC_SUCCESS			0xE0
#define RC_INVALIDCOMMAND   0xE1
#define RC_ESCPRESSED		0xE2
#define RC_BUFOVFLW			0xE3
#define RC_INVALIDDATASIZE  0xE4
#define RC_HANDSHAKEERR		0xE5
#define RC_FILENOTFOUND		0xE6
#define RC_FAILED			0xE7
#define RC_CONNERR			0xE8
#define RC_WAIT				0xE9
#define RC_READY			0xEA
#define RC_SUCCNOSTD		0xEB
#define RC_FAILNOSTD		0xEC
#define RC_TERMINATE		0xED
#define RC_UNEXPECTEDDATA	0xEE
#define RC_UNDEFINED		0xEF

#define CHK_STATE_0       0
#define CHK_STATE_2       2

#define PAGE1ADDRESS ((uint8_t*)0x4000)
#define PAGE2ADDRESS ((uint8_t*)0x8000)


extern unsigned int heap_top;
void pprintf(char* text, uint16_t value);
void pprints(char* text, char* value);
void FastPrint(char* text);
char* GetCmdLineParameters(void);
uint8_t CHKPIRDY(void);
uint8_t PIREADBYTE(uint8_t* byte);
uint8_t PIWRITEBYTE(uint8_t data);
uint8_t RECVDATA(uint8_t* dest, uint16_t* size, uint16_t* maxbufsize);
uint8_t RECVDATA_ONEBLOCK(uint8_t* dest, uint16_t* size, uint16_t maxbufsize);
// The library defines SENDDATA2; this was declared as SENDDATA, which no
// caller had exercised until pcopy started uploading.
uint8_t SENDDATA2(uint8_t* src, uint16_t size, uint16_t* maxbufsize);
uint8_t PerformHandshake(uint16_t msx_blocksize);
uint8_t SendCommandToMSXPi(const char* cmd, bool appendDOSParameters);
uint8_t parseConnError(const uint8_t rc);
uint16_t get_sp(void) __naked;
uint16_t get_max_buffer_size(void);
uint8_t* get_buffer_ptr(void);
uint8_t printstdout(uint8_t* buffer, uint16_t maxbufsize);

// Shared-link guard - see msxpi-bios.c.  Claim before an exchange with the Pi
// and release after, so the Ethernet UNAPI ISR does not transmit in the middle
// of it.  No-ops when no Ethernet UNAPI is installed.
void msxpi_link_claim(void) __naked;
void msxpi_link_release(void) __naked;
uint8_t msxpi_exchange(const char* cmd, bool appendTail, uint8_t* buffer, uint16_t maxbufsize);
