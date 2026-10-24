/*
 * MSXPi Interface
 * Version 1.6.1
 * ------------------------------------------------------------------------------
 * MIT License
 *
 * Copyright (c) 2015-2026 Ronivon Costa
 * (see the licence text at the top of C-common/header/fusion.h)
 * ------------------------------------------------------------------------------
 */

/* The C functions of fusion.h, compiled with the calling convention of the program. */
#include "../header/fusion.h"

/* '\n' is sent as LF CR, as Fusion-C's Print does. */
void Print(char *text)
{
    char c;

    while ((c = *text++) != 0) {
        if (c == '\n') {
            PrintChar(10);
            PrintChar(13);
        } else {
            PrintChar(c);
        }
    }
}

/* Unsigned decimal, no padding. */
void PrintNumber(unsigned int num)
{
    char digits[5];
    unsigned char n = 0;

    do {
        digits[n++] = '0' + num % 10;
        num /= 10;
    } while (num);
    while (n)
        PrintChar(digits[--n]);
}

/* Columns of the text screen: SCREEN 0 or 1 is set again to take effect. */
void Width(char n)
{
    unsigned char mode = Peek(SCRMOD);

    if (mode == 0) {
        Poke(0xF3AE, n);
        Screen(0);
    } else if (mode == 1) {
        Poke(0xF3AF, n);
        Screen(1);
    }
}

/* Highest address of the TPA, from the BDOS entry at 0006h. */
unsigned int ReadTPA(void)
{
    return Peekw(0x0006);
}
