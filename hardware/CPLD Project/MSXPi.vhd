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



architecture rtl of MSXPi is
constant MSXPIVer : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1001";
constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
constant CTRLPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"58";
constant CTRLPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"59";
constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
constant DATAPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"5B";
constant DATAPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"5C";
constant DATAPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"5D";
    type fsm_type is (idle, prepare, transferring);
    signal spi_state    : fsm_type := idle;
    signal readoper     : std_logic;
    signal writeoper    : std_logic;
    signal csPin       : std_logic;
    signal D_buff_msx   : std_logic_vector(7 downto 0);
    signal D_buff_pi    : std_logic_vector(7 downto 0);
    signal RESET        : std_logic;
    signal spibitcount_s: integer range 0 to 8;
    signal D_buff_msx_r : std_logic_vector(7 downto 0);
    signal SPI_en_s     : STD_LOGIC := '0';
    signal waitSignal    : STD_LOGIC;
    signal clk: std_logic;
    
begin

    SPI_CS <= csPin;                        -- Enable singal for RPi
    WAIT_n <= waitSignal;                -- Z80 /wait signal
    clk <= SPI_SCLK;                        -- Serial clock from RPi
    
    readoper   <= not (IORQ_n or RD_n);
    writeoper  <= not (IORQ_n or WR_n);

process(IORQ_n, WR_n, RD_n, waitSignal, SPI_RDY)
begin
    if (IORQ_n = '0' and (WR_n = '0' or RD_n = '0')) then        -- a new read/write request from MSX
         csPin <= '0';
         waitSignal <= '0';
    elsif csPin = '0' and SPI_RDY = '1' then                            -- RPi is selected and signaling ready
        csPin <= '1';
        waitSignal <= '1';
    elsif SPI_RDY = '1' then
        waitSignal <= 'Z';
    end if;
end process;

process(SPI_SCLK)
begin
    D_buff_pi <= D_buff_pi(6 downto 0) & SPI_MISO;
    SPI_MOSI <= D_buff_msx_r(7);
    D_buff_msx_r(7 downto 1) <= D_buff_msx_r(6 downto 0);
end process;

end rtl;
