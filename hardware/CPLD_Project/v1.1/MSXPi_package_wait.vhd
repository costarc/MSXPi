-- MSXPi v1.6 CPLD firmware for the v1.1 and v1.2.1b boards (PCB V1.1 Rev.1 and V1.2.1b, AT28C256 EEPROM, pin map B)
-- Build: /WAIT flow control, build ID $14 at $57 bits 5-0.
-- pin 28 = WAIT_n, must reach slot pin 7 (/WAIT).
-- Shares ../MSXPi.vhd with the main v1.6 build; only this package differs.
library ieee;
use ieee.std_logic_1164.all;

package MSXPi_package is
    constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
    constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
    constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
    constant MSXPIVer : STD_LOGIC_VECTOR(5 DOWNTO 0) := "010100";   -- $14
    constant WAIT_SUPPORT : boolean := true;
    -- True only for the v0.8.2 board, whose WAIT_n pin drives the LED.
    constant WAIT_PIN_IS_LED : boolean := false;
    constant WAITMODE_ON  : STD_LOGIC_VECTOR(7 downto 0) := x"01";
    constant WAITMODE_OFF : STD_LOGIC_VECTOR(7 downto 0) := x"00";
end MSXPi_package;
