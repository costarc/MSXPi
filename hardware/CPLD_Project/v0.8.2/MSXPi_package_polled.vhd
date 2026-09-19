-- MSXPi v1.6 CPLD firmware for the v0.8.2 and v1.0 releases (both PCB v0.7 Rev.7, 27C256 EPROM, pin map A)
-- Build: polled only (no /WAIT), build ID $10 at $57 bits 5-0.
-- pin 8 drives the on-board LED, not the slot /WAIT line, so it is
-- driven as the LED (WAIT_PIN_IS_LED): off until msxpi-server.py
-- announces itself online, flickering on transfers, off again when it goes
-- offline.
-- Shares ../MSXPi.vhd with the main v1.6 build; only this package differs.
library ieee;
use ieee.std_logic_1164.all;

package MSXPi_package is
    constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
    constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
    constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
    constant MSXPIVer : STD_LOGIC_VECTOR(5 DOWNTO 0) := "010000";   -- $10
    constant WAIT_SUPPORT : boolean := false;
    -- True only for the v0.8.2 board, whose WAIT_n pin drives the LED.
    constant WAIT_PIN_IS_LED : boolean := true;
    constant WAITMODE_ON  : STD_LOGIC_VECTOR(7 downto 0) := x"01";
    constant WAITMODE_OFF : STD_LOGIC_VECTOR(7 downto 0) := x"00";
end MSXPi_package;
