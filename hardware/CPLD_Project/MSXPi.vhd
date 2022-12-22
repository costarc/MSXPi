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
-- Version 1.0.1 - 2022-12-21
-- Redesigned the CPLD firmware / code
-- Serial protocol - MSX Reading data:
--	
--		Enable SPI_CS - '0'
--		Enable MSX /Wait - '0'
--		RPi Disable SPI_RDY - '1'
--		Wait RPi clock rising event on pin SPI_SCLK
--		1st Tick is for sync, no valid data present in SPI_MISO
--    Next 8 Ticks contain 8 bits of data in SPI_MISO
--		Move Data to Latch D - ready for MSX D register
--    1 Tick for sync / cleanup
-- 	RPi Enable SPY_RDY - '0'
--		Disable SPI_CS - '1'
--		Disable MSX /Wait - 'Z'
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
-- 1011: General Release V1.0.1, EEPROM AT28C256, EPM3064ALC-44
-- ----------------------------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all;
--use IEEE.STD_LOGIC_UNSIGNED.ALL;

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
constant MSXPIVer : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1011";
constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
constant CTRLPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"58";
constant CTRLPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"59";
constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
constant DATAPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"5B";
constant DATAPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"5C";
constant DATAPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"5D";

   signal csPinSignal	: std_logic;
   signal csPin_s1		:std_logic;
	signal csPin_s2		: std_logic;
		
	signal D_buff_pi		: std_logic_vector(7 downto 0);
	signal RESET			: std_logic;
	signal D_buff_msx		: std_logic_vector(7 downto 0);
	signal waitSignal		: STD_LOGIC := 'Z';
	signal msxwrite_s		: STD_LOGIC;
	signal msxread_s		: STD_LOGIC;
	signal spi_count_s0	: std_logic_vector(3 downto 0) := "0000";
	signal spi_count_s	: std_logic_vector(3 downto 0) := "0000";
	signal spi_rdysignal	: std_logic;
	
	signal reg1: std_logic_vector(7 downto 0);
    
begin
  
   spi_rdysignal <= SPI_RDY;
	csPinSignal <= msxwrite_s and msxread_s and not spi_rdysignal;
	SPI_CS <= csPinSignal;
	WAIT_n <= csPinSignal when csPinSignal = '0' else 'Z';
		
	msxwrite_s <= '0' when IORQ_n ='0' and WR_n = '0' and A = DATAPORT1 else '1';
	msxread_s <= '0' when IORQ_n ='0' and RD_n = '0' and A = DATAPORT1 else '1';

	
	--D_buff_msx <= D when msxwrite_s = '0' and A = DATAPORT1;
	D <= D_buff_pi; -- when msxread_s = '0' and A = DATAPORT1 and SPI_RDY = '1' else
   --     SPI_RDY & csPin & "00" & MSXPIVer when msxread_s = '0' and A = DATAPORT1 and SPI_RDY = '0' else
	--	  "ZZZZZZZZ";

process(SPI_SCLK)
variable D_reg : std_logic_vector(7 downto 0);
begin
	if rising_edge(SPI_SCLK) then
		if to_integer(unsigned(spi_count_s)) < 8 then
			D_buff_pi <= D_buff_pi(6 downto 0) & SPI_MISO;
			SPI_MOSI <= D_reg(7);
			D_reg(7 downto 1) := D_reg(6 downto 0);
			spi_count_s <= std_logic_vector(to_unsigned(to_integer(unsigned(spi_count_s)) + 1, 4));
		else
			spi_count_s <= "0000";
		end if;
	end if;
	
	--reg1 <= D_buff_pi;
	
end process;

end rtl;
