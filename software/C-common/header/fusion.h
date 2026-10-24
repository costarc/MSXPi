/*
 * MSXPi Interface
 * Version 1.6.1
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

/*
 * The part of the Fusion-C library the MSXPi programs use, declared for SDCC 4.6
 * (the SDCC 4.6 port, documents/SDCC46-PORT-HANDOVER.md).
 *
 * The Fusion-C routines written in assembler (tools/build_fusion46.py assembles them from the
 * Fusion-C source tree into fusion46.lib) take their arguments on the stack and return in L/HL:
 * they are declared __sdcccall(0), so they mean the same whatever convention the program is
 * compiled with. Print, PrintNumber, Width and ReadTPA are C and live in C-common/fusion/.
 *
 * Fusion-C is by Eric Boez and Fernando Garcia (msx_fusion.h is the original, for the
 * programs not ported yet).
 */
#ifndef MSXPI_FUSION_H
#define MSXPI_FUSION_H

#ifndef NULL
#define NULL (void *)0
#endif

#define FCB_SUCCESS 0x00
#define FCB_ATTR_READONLY 0x01
#define FCB_ATTR_HIDDEN 0x02
#define FCB_ATTR_SYSTEM 0x04
#define FCB_ATTR_VOLUME 0x08
#define FCB_ATTR_DIR 0x10
#define FCB_ATTR_ARCHIVE 0x20

#define SCRMOD 0xFCAF      /* current screen mode */
#define ACPAGE 0xFAF6      /* active page number */
#define DPPAGE 0xFAF5      /* display page number */

#define Poke(address, data)  (*((volatile unsigned char *)(address)) = ((unsigned char)(data)))
#define Pokew(address, data) (*((volatile unsigned int *)(address)) = ((unsigned int)(data)))
#define Peek(address)        (*((volatile unsigned char *)(address)))
#define Peekw(address)       (*((volatile unsigned int *)(address)))

#define WaitForKey WaitKey
#define KeyboardHit Inkey

typedef struct {
    unsigned char drive_no;
    unsigned char name[8];
    unsigned char ext[3];
    unsigned int current_block;
    unsigned int record_size;
    unsigned long file_size;
    unsigned int date;
    unsigned int time;
    unsigned char device_id;
    unsigned char directory_location;
    unsigned int start_cluster_no;
    unsigned int last_access_cluster_no;
    unsigned int cluster_offset;
    unsigned char current_record;
    unsigned long random_record;
} FCB;

typedef struct {
    unsigned char name[8];
    unsigned char ext[3];
    unsigned char attribute;
    unsigned char undel_char;
    unsigned char reserve[9];
    unsigned int time;
    unsigned int date;
    unsigned int start_cluster_no;
    unsigned long file_size;
} FCB_DIR;

typedef struct {
    unsigned char drive_no;
    FCB_DIR dirinfo;
} FCB_FIND;

/* C: built with the program's calling convention */
void Print(char *text);
void PrintNumber(unsigned int num);
void Width(char n);
unsigned int ReadTPA(void);

/* Assembler: stack arguments, result in L/HL */
void Cls(void) __sdcccall(0);
void PrintChar(char c) __sdcccall(0);
void Locate(char x, char y) __sdcccall(0);
void PutCharHex(char c) __sdcccall(0);
char InputChar(void) __sdcccall(0);
unsigned char WaitKey(void) __sdcccall(0);
unsigned char Inkey(void) __sdcccall(0);
void FunctionKeys(char n) __sdcccall(0);
char ReadMSXtype(void) __sdcccall(0);
void Screen(unsigned char mode) __sdcccall(0);
void SetColors(unsigned char foreground, unsigned char background, unsigned char border) __sdcccall(0);
unsigned char JoystickRead(char joyNumber) __sdcccall(0);
unsigned char TriggerRead(char TriggerNumber) __sdcccall(0);
void OutPort(unsigned char port, unsigned char data) __sdcccall(0);
unsigned char InPort(unsigned char port) __sdcccall(0);
void VDPwrite(unsigned char vdpreg, unsigned char data) __sdcccall(0);
void HideDisplay(void) __sdcccall(0);
void ShowDisplay(void) __sdcccall(0);
void FillVram(int Startadress, char value, int length) __sdcccall(0);
void CopyRamToVram(void *SrcRamAddress, unsigned int DestVramAddress, unsigned int Length) __sdcccall(0);
void CopyVramToRam(unsigned int SrcVramAddress, void *DestRamAddress, unsigned int Length) __sdcccall(0);
void StrCopy(char *dst, char *src) __sdcccall(0);
int StrCompare(char *s1, char *s2) __sdcccall(0);
int IsDigit(char c) __sdcccall(0);
unsigned int ReadSP(void) __sdcccall(0);
int SetDate(int Year, char month, char day) __sdcccall(0);
unsigned char fcb_open(FCB *p_fcb) __sdcccall(0);
unsigned char fcb_create(FCB *p_fcb) __sdcccall(0);
unsigned char fcb_close(FCB *p_fcb) __sdcccall(0);
unsigned int fcb_read(FCB *p_fcb, void *p_buffer, int size) __sdcccall(0);
unsigned char fcb_write(FCB *p_fcb, const void *p_buffer, int size) __sdcccall(0);
unsigned char fcb_find_first(FCB *p_fcb, FCB_FIND *p_result) __sdcccall(0);
unsigned char fcb_find_next(FCB_FIND *p_result) __sdcccall(0);

#endif
