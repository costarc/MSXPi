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
----------------------------------------------------------------------------------
-- version 0.7
-- Added signal BUSDIR
----------------------------------------------------------------------------------
-- Version 0.7 Rev 4 - 2017-07-22
-- Added package msxpi_package with PORTS definition
-- Modified ports (from 6,7,8) to range 0x56 - 0x5D
----------------------------------------------------------------------------------
-- Version 0.9 Rev 0 - 2020-07-10
-- Removed package msxpi_package with PORTS definition - why I added by the way?
-- Replaced BUSDIR by WAIT. Needs mod in the interface
-- Added CPLD suppport for /WAIT signal, still compatible with previous versions
----------------------------------------------------------------------------------
-- MSXPi PCB revisions supported by this design:
-- 
-- 0001: Wired up prototype, without EPROM,EPM3064ALC-44
-- 0010: Semi-wired up prototype, with EPROM, EPM3064ATC-44
-- 0011: Limited 10-samples PCB, with EPROM, EPM3064ALC-44
-- 0100: Limited 1 sample PCB, with EPROM, EPM3064ALC-44, 4 bits mode.
-- 0101: Limited 10 samples PCB Rev.3, EPROM, EPM3064ALC-44
-- 0110: Wired up prototype, with EPROM, EPM7128SLC-84
-- 0111: Rev.4 batch, EPM3064ALC-44 (First public release)
-- 1000: Limited 10 samples, Big v0.8.1 Rev.0, EPM7128SLC-84, not released
-- 1001: Rev.4 or later with /Wait mod, with EPROM, EPM3064ALC-44
--
-- ----------------------------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all;
--use work.msxpi_package.all;

ENTITY MSXInterface IS
PORT ( 
    D           : INOUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    A           : IN STD_LOGIC_VECTOR(7 DOWNTO 0);
    IORQ_n      : IN STD_LOGIC;
    RD_n        : IN STD_LOGIC;
    WR_n        : IN STD_LOGIC;
    WAIT_n      : OUT STD_LOGIC;
    --
    SPI_CS      : OUT STD_LOGIC;
    SPI_SCLK    : IN STD_LOGIC;
    SPI_MOSI    : OUT STD_LOGIC;
    SPI_MISO    : IN STD_LOGIC;
    SPI_RDY     : IN STD_LOGIC;
    --
    LED         : OUT STD_LOGIC);
END MSXInterface;

architecture rtl of MSXInterface is

    constant MSXPIVer   : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1001";
    constant DATAPORT   : STD_LOGIC_VECTOR(7 downto 0) := x"5A";
    constant CTRLPORT1  : STD_LOGIC_VECTOR(7 downto 0) := x"5B";
    constant CTRLPORT2  : STD_LOGIC_VECTOR(7 downto 0) := x"5C";

    
    
    type fsm_type is (start,transferring);
    signal state : fsm_type := start;
    
    signal readoper_s     : std_logic;
    signal writeoper_s    : std_logic;
    signal rpi_en_s       : std_logic;
    signal D_buff_msx_s   : std_logic_vector(7 downto 0);
    signal D_buff_pi_s    : std_logic_vector(7 downto 0);  
    signal wait_n_s       : std_logic := 'Z';
    signal rpi_enabled_s  : std_logic := '0';
    signal msxpi_status_s : std_logic;
	 
begin

    LED    <= rpi_enabled_s;
    SPI_CS <= not rpi_enabled_s;
    WAIT_n <= wait_n_s;

    --WAIT_n <= '0' when state = transferring else
	--           '0' when SPI_MISO = '0' else 'Z';
    
	 --   msxpi_status_s <= "00" when SPI_MISO = '1' and rpi_enabled_s = '0' else
     --                  "01" when SPI_MISO = '0' and rpi_enabled_s = '0' else
     --                       "10";

    readoper_s  <= not (IORQ_n or RD_n);
    writeoper_s <= not (IORQ_n or WR_n);
    rpi_en_s    <= '1' when (A = DATAPORT and (writeoper_s = '1' or readoper_s = '1')) else '0';

    D <= "0000000" & (not SPI_MISO) when (readoper_s = '1' and A = CTRLPORT1) else   
         D_buff_pi_s when readoper_s = '1' and A = DATAPORT else
         "0000" & MSXPIVer when (readoper_s = '1' and A = CTRLPORT2) else 
         "ZZZZZZZZ";

    -- Triggers the interface
    process(rpi_en_s, SPI_RDY)
    begin
        if (SPI_RDY = '0') then
            rpi_enabled_s <= '0';
            wait_n_s <= 'Z';
        elsif (rising_edge(rpi_en_s)) then
            wait_n_s <= '0';
            rpi_enabled_s <= '1';
         end if;
    end process;

    -- Initialize serial/paralell process
    process(rpi_enabled_s,rpi_en_s,SPI_SCLK)
    begin
        if (rpi_enabled_s = '0') then
            state <= start;
        elsif rising_edge(SPI_SCLK) then
            state <= transferring;
        end if;
    end process;
    
    -- Convert MSX data to serial / RPi serial to paralell
    -- Send bits to RPi in serial mode, receive RPi bits and latches
    process(SPI_SCLK)
    begin
         if (state = start) then
            D_buff_msx_s <= D;
        elsif rising_edge(SPI_SCLK) then
            D_buff_pi_s <= D_buff_pi_s(6 downto 0) & SPI_MISO;
            SPI_MOSI <= D_buff_msx_s(7);
            D_buff_msx_s(7 downto 1) <= D_buff_msx_s(6 downto 0);
        end if;
    end process;
end rtl;