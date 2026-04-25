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