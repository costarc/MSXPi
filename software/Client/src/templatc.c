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

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include "../../../../../MSX-C/WorkingFolder/fusion-c/header/msx_fusion.h"
#include "../../C-common/header/msxpi.h"

int main(void)
{

    /*
	SendCommandToMSXPi(<command>, <appendDosTail>) 
        Send a command to MSXPi, and optionally append the DOS command line parameters
    
	Supported command formats are:

	- SendCommandToMSXPi("", true): Send only DOS parameters. This is how the p.com command works.
        Exemple: p.com ver
        In this case, only the command "ver" is sent (which is the DOS parameter passed at command line) 

	- SendCommandToMSXPi("template", false): Send only the "template" command without any DOS parameters.

	- SendCommandToMSXPi("template", true): Send command "template" along with any DOS parameters.
		Example: template.com string or list of arguments
		MSXPi will execute the function template() and receive parameter "string or list of arguments".

	printstdout(<Buffer Size>): Prints thhe respons to screen.
		Buffer size should be set to a value that woni't exceed the computer capacity. BLKSIZE is
		recommended for most computers.
    */
    uint8_t rc = SendCommandToMSXPi("template", true);
    if (rc == RC_SUCCESS || rc == RC_FAILED) {
        uint8_t* buffer = (uint8_t*)(get_buffer_ptr() + 100);
        printstdout(buffer, MAXBUFSIZE);
    }

    return 0;
}