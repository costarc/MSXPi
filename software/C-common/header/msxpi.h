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

#define PAGE0ADDRESS ((uint8_t*)0x4000)
#define PAGE1ADDRESS ((uint8_t*)0x8000)

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
uint8_t SENDDATA(uint8_t* src, uint16_t size, uint16_t* maxbufsize);
uint8_t PerformHandshake(uint16_t msx_blocksize);
uint8_t SendCommandToMSXPi(const char* cmd, bool appendDOSParameters);
uint8_t parseConnError(const uint8_t rc);
uint16_t get_sp(void) __naked;
uint16_t get_max_buffer_size(void);
uint8_t* get_buffer_ptr(void);
uint8_t printstdout(uint8_t* buffer, uint16_t maxbufsize);
