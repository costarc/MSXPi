-- Ronivon Candido Costa
-- 22/10/2016
-- MSX_Interface using new proto board
-- Receives 8 bits on D bus, convert to serial and send to external IO (SPI pins)
----------------------------------------------------------------------------------
-- CPLD: V0.5
-- MSX: bootv5.bin
-- Pi: msx.c (v1.5)
----------------------------------------------------------------------------------
-- Version 0.5
-- For prototype 2, with Pi Zero attached on the cart.
-- Ports:
-- 07 - Data (read/write data)
-- 06 - Control:
--          (Write) 0xFF - Reset
--          (Write) 0x00 - Read command
--          (Read)       - SPI status, 0 = busy, 1 = data ready
--          
----------------------------------------------------------------------------------
-- version 0.6
-- Added signal RDY to control data flow between MSX,CPLD and Pi.
-- SPI_RDY Low  = Ready
-- SPI_RDY HIGH = Busy
--
----------------------------------------------------------------------------------
-- version 0.7
-- Added signal BUSDIR
----------------------------------------------------------------------------------
-- Version 0.7 Rev 4 - 2017-07-22
-- Added package msxpi_package with PORTS definition
-- Modified ports (from 6,7,8) to range 0x56 - 0x5D
----------------------------------------------------------------------------------
-- Version 1.0 Rev 0 - 2020-08-01
-- Added support to /Wait signal (using LED pin)
-- LED now is drived by SPI_CS signal
----------------------------------------------------------------------------------
-- Version 1.0.1 - 2022-12-25
-- Firmaware version number updated to "1010" to identify new PCB v1.0.1"
-- No other changes made to this design
-- -------------------------------------------------------------------------------
-- MSXPI Versions:
-- 0001: Wired up prototype, EPM3064ALC-44
-- 0010: Semi-wired up prototype, EPROM 27C256, EPM3064ATC-44
-- 0011: Limited 10-samples PCB, EPROM 27C256, EPM3064ALC-44
-- 0100: Limited 1 sample PCB, EPROM 27C256, EPM3064ALC-44, 4 bits mode.
-- 0101: Limited 10 samples PCB Rev.3, EPROM 27C256, EPM3064ALC-44
-- 0110: Wired up prototype, EPROM 27C256, EPM7128SLC-84
-- 0111: General Release V0.7 Rev.4, EPROM 27C256, EPM3064ALC-44
-- 1000: Prototype 10 samples, Big v0.8.1 Rev.0, EPM7128SLC-84
-- 1001: General Release V1.0 Rev 0, EPROM 27C256, EPM3064ALC-44
-- 1010: General Release V1.1 Rev 0, EEPROM AT28C256, EPM3064ALC-44
-- ----------------------------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all;
use work.msxpi_package.all;

ENTITY MSXPi IS
PORT ( 
    D           : INOUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    A           : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    IORQ_n      : IN STD_LOGIC;
    RD_n        : IN STD_LOGIC;
    WR_n        : IN STD_LOGIC;
    BUSDIR_n    : OUT STD_LOGIC;
    WAIT_n      : OUT STD_LOGIC;
    --
    SPI_CS      : OUT STD_LOGIC;
    SPI_SCLK    : IN STD_LOGIC;
    SPI_MOSI    : OUT STD_LOGIC;
    SPI_MISO    : IN STD_LOGIC;
    SPI_RDY     : IN STD_LOGIC);
END MSXPi;

library ieee;
use ieee.std_logic_1164.all;
package msxpi_package is
        constant MSXPIVer : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1010";
        constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
        constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
        constant CTRLPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"58";
        constant CTRLPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"59";
        constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
        constant DATAPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"5B";
        constant DATAPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"5C";
        constant DATAPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"5D";
end msxpi_package;

architecture rtl of MSXPi is
    type fsm_type is (idle, prepare, transferring);
    signal spi_state    : fsm_type := idle;
    signal readoper     : std_logic;
    signal writeoper    : std_logic;
    signal spi_en       : std_logic;
    signal D_buff_msx   : std_logic_vector(7 downto 0);
    signal D_buff_pi    : std_logic_vector(7 downto 0);
    signal RESET        : std_logic;
    signal spibitcount_s: integer range 0 to 8;
    signal D_buff_msx_r : std_logic_vector(7 downto 0);
    signal SPI_en_s     : STD_LOGIC := '0';
    signal SPI_RDY_s    : STD_LOGIC;
    
begin

    WAIT_n <= 'Z';
    BUSDIR_n <= '0' when (readoper = '1' and (A = CTRLPORT1 or A = DATAPORT1)) else '1';
    readoper   <= not (IORQ_n or RD_n);
    writeoper  <= not (IORQ_n or WR_n);
    spi_en     <= '1' when writeoper = '1' and (A = CTRLPORT1 or A = DATAPORT1) else
                     '0';
    
    -- SPI_en_s = '1' means SPI is busy
    -- SPI_RDY  = '1' means Pi is Busy
    SPI_RDY_s <= SPI_en_s or (not SPI_RDY);
    RESET <= '1' when writeoper = '1' and A = CTRLPORT1 and D = x"FF" else '0';
    D_buff_msx <= D when writeoper = '1' and (A = CTRLPORT1 or A = DATAPORT1);
    D <= "0000000" & SPI_RDY_s when (readoper = '1' and A = CTRLPORT1) else     
         D_buff_pi when readoper = '1' and A = DATAPORT1 else
          "0000" & MSXPIVer when (readoper = '1' and A = CTRLPORT2) else 
          "ZZZZZZZZ";

spi:process(SPI_SCLK,readoper,writeoper,RESET)
begin
    if RESET = '1' then
        SPI_en_s <= '0';
        D_buff_pi <= "00000000";
        spi_state <= idle;
    elsif (SPI_en_s = '0' and spi_en = '1') then
        SPI_en_s <= '1';
        spibitcount_s <= 0;
        spi_state <= prepare;
    elsif rising_edge(SPI_SCLK) then
        case spi_state is
            when idle =>
                SPI_en_s <= '0';
            when prepare  =>
                D_buff_msx_r <= D_buff_msx;
                spi_state <= transferring;
            when transferring =>
                D_buff_pi <= D_buff_pi(6 downto 0) & SPI_MISO;
                SPI_MOSI <= D_buff_msx_r(7);
                D_buff_msx_r(7 downto 1) <= D_buff_msx_r(6 downto 0);
                spibitcount_s <= spibitcount_s + 1;
                if spibitcount_s > 6 then
                        spi_state <= idle;
                end if;
        end case;
    end if;

    SPI_CS <= not SPI_en_s;

end process;
end rtl;
