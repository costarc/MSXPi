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
-- Added support to /wait signal (using LED pin)
-- LED now is drived by SPI_CS signal
----------------------------------------------------------------------------------
-- Version 1.1 Rev 2 - 2020-09-03
-- Added full support to /wait signal on PCB v1.1
-- Redesigned the logic to support /wait and bus data (no longer only data bus)
-- "piexchange" now should read byte from dataport2 (save one iteration cycle with RPi
----------------------------------------------------------------------------------
-- MSXPI Versions:
-- 0001: Wired up prototype, without EPROM,EPM3064ALC-44
-- 0010: Semi-wired up prototype, with EPROM, EPM3064ATC-44
-- 0011: Limited 10-samples PCB, with EPROM, EPM3064ALC-44
-- 0100: Limited 1 sample PCB, with EPROM, EPM3064ALC-44, 4 bits mode.
-- 0101: Limited 10 samples PCB Rev.3, EPROM, EPM3064ALC-44
-- 0110: Wired up prototype, with EPROM, EPM7128SLC-84
-- 0111: General Release v0.7 Rev.4 - Rev.7, EPM3064ALC-44
-- 1000: Limited 10 samples, Big v0.8.1 Rev.0, EPM7128SLC-84
-- 1001: General Release V1.1, EPM3064ALC44-10, EEPROM AT28C256
-- ----------------------------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all;
use work.msxpi_package.all;

ENTITY MSXInterface IS
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
END MSXInterface;

library ieee;
use ieee.std_logic_1164.all;
package msxpi_package is
        constant MSXPIVer : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1001";
        constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
        constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
        constant CTRLPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"58";
        constant CTRLPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"59";
        constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
        constant DATAPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"5B";
        constant DATAPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"5C";
        constant DATAPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"5D";
end msxpi_package;

architecture rtl of MSXInterface is
    type fsm_type is (start,transferring);
    signal state : fsm_type := start;
    
    signal readoper_s     : std_logic;
    signal writeoper_s    : std_logic;
    signal rpi_en_s       : std_logic;
    signal msxbus_s       : std_logic_vector(16 downto 0);
	 signal msxbusbuf_s    : std_logic_vector(16 downto 0);
    signal D_buff_pi_s    : std_logic_vector(7 downto 0);  
    signal wait_n_s       : std_logic := 'Z';
    --signal msxpiserver    : std_logic := '0';
    signal msxpi_state    : std_logic := '0';
    
begin

    WAIT_n <= wait_n_s;
    -- SPI_CS <= not rpi_enabled_s;
	 SPI_CS <= not msxpi_state;
    BUSDIR_n <= '0' when (readoper_s = '1' and (A = CTRLPORT1 or A = CTRLPORT2 or A = DATAPORT1)) else '1';

    readoper_s   <= not (IORQ_n or RD_n);
    writeoper_s  <= not (IORQ_n or WR_n);

    rpi_en_s    <= '1' when (A = DATAPORT1 and (writeoper_s = '1' or readoper_s = '1')) else '0';

    D <= "0000000" & msxpi_state when (readoper_s = '1' and A = CTRLPORT1) else     
         D_buff_pi_s when readoper_s = '1' and (A = DATAPORT1 or A = DATAPORT2) else
          "0000" & MSXPIVer when (readoper_s = '1' and A = CTRLPORT2) else 
          "ZZZZZZZZ";

    -- This process detects when msxpi-server component has initialized
    -- If it has not started, /wait signal should not be enabled to allow MSX to start
    -- Once it has ticked one time, we know msxpi-server has started,
    -- then /wait can start to be driven by that rpi_rdy signal.
    --process(SPI_RDY)
    --begin
    --    if (rising_edge(SPI_RDY)) then
    --        msxpiserver <= '1';
    --     end if;
    --end process;

    -- Triggers the interface
    process(rpi_en_s, SPI_RDY)
    begin
        if (SPI_RDY = '0') then
            msxpi_state <= '0';
            wait_n_s <= 'Z';
        elsif (rising_edge(rpi_en_s)) then
            wait_n_s <= '0';
            msxpi_state <= '1';
				msxbusbuf_s <= WR_n & A & D;
         end if;
    end process;

    -- Initialize serial/paralell process
    process(msxpi_state,SPI_SCLK)
    begin
        if (msxpi_state = '0') then
            state <= start;
        elsif rising_edge(SPI_SCLK) then
            state <= transferring;
        end if;
    end process;
    
    -- Convert MSX data to serial / RPi serial to parallel
    -- Send bits to RPi in serial mode, receive RPi bits and latches
    process(SPI_SCLK)
    begin
         if (state = start) then
            msxbus_s <= msxbusbuf_s;
        elsif rising_edge(SPI_SCLK) then
            D_buff_pi_s <= D_buff_pi_s(6 downto 0) & SPI_MISO;
            SPI_MOSI <= msxbus_s(16);
            msxbus_s(16 downto 1) <= msxbus_s(15 downto 0);
        end if;
    end process;
end rtl;

