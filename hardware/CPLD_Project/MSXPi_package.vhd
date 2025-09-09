library ieee;
use ieee.std_logic_1164.all;

package MSXPi_package is

        constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
		  constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
        constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
		  constant MSXPIVer : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1011";

end MSXPi_package;
