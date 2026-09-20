library ieee;
use ieee.std_logic_1164.all;

package MSXPi_package is
    constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
    constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
    constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
    -- Firmware build ID, read at $57 bits 5-0 (see LEGACY_BOARDS.md for the
    -- full table).  $0E = v1.6 on PCB V1.3 Rev.1 (pin map C: releases v1.3 to v1.6).
    constant MSXPIVer : STD_LOGIC_VECTOR(5 DOWNTO 0) := "001110";
    -- True when the board routes WAIT_n to the cartridge /WAIT line, so the
    -- $57 wait-mode register exists.  False makes it a constant '0'.
    constant WAIT_SUPPORT : boolean := true;
    -- True only for the v0.8.2 board, whose WAIT_n pin drives the LED.
    constant WAIT_PIN_IS_LED : boolean := false;
    -- Value written to CTRLPORT2 to turn hardware /WAIT flow control on/off
    constant WAITMODE_ON  : STD_LOGIC_VECTOR(7 downto 0) := x"01";
    constant WAITMODE_OFF : STD_LOGIC_VECTOR(7 downto 0) := x"00";
end MSXPi_package;
