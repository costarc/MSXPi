library ieee;
use ieee.std_logic_1164.all;

package msxpi_package is

    -- Firmware version
    constant MSXPIVer : std_logic_vector(3 downto 0) := "1011";

    -- Control ports
    constant CTRLPORT1 : std_logic_vector(7 downto 0) := x"56";
    constant CTRLPORT2 : std_logic_vector(7 downto 0) := x"57";
    constant CTRLPORT3 : std_logic_vector(7 downto 0) := x"58";
    constant CTRLPORT4 : std_logic_vector(7 downto 0) := x"59";

    -- Data ports
    constant DATAPORT1 : std_logic_vector(7 downto 0) := x"5A";
    constant DATAPORT2 : std_logic_vector(7 downto 0) := x"5B";
    constant DATAPORT3 : std_logic_vector(7 downto 0) := x"5C";
    constant DATAPORT4 : std_logic_vector(7 downto 0) := x"5D";

end msxpi_package;
