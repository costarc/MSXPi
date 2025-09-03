library ieee;
use ieee.std_logic_1164.all;

package msxpi_package is

    -- Control ports
    constant CTRLPORT1 : std_logic_vector(7 downto 0) := x"56";
    -- Data ports
    constant DATAPORT1 : std_logic_vector(7 downto 0) := x"57";


end msxpi_package;
