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
--			(Write) 0xFF - Reset
--			(Write) 0x00 - Read command
--			(Read)       - SPI status, 0 = busy, 1 = data ready
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
-- 1000: Rev.4 or later with /WAIT mod, or PCB Rev.8, with EPROM, EPM3064ALC-44
--
-- ----------------------------------------------------------------------------------
library ieee ;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all;
--use work.msxpi_package.all;

ENTITY MSXInterface IS
PORT ( 
	D			: INOUT STD_LOGIC_VECTOR(7 DOWNTO 0);
	A			: IN STD_LOGIC_VECTOR(7 DOWNTO 0);
	IORQ_n	: IN STD_LOGIC;
	RD_n		: IN STD_LOGIC;
	WR_n		: IN STD_LOGIC;
	WAIT_n	: OUT STD_LOGIC;
	--
	SPI_CS	: OUT STD_LOGIC;
	SPI_SCLK	: IN STD_LOGIC;
	SPI_MOSI	: OUT STD_LOGIC;
	SPI_MISO	: IN STD_LOGIC;
	SPI_RDY  : IN STD_LOGIC;
	--
	LED		: OUT STD_LOGIC
);
END MSXInterface;

architecture rtl of MSXInterface is

	--constant MSXPIVer : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0111";
	constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
	constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
	constant CTRLPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"58";
	constant CTRLPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"59";
	constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
	constant DATAPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"5B";
	constant DATAPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"5C";
	constant DATAPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"5D";

	type fsm_type is (idle, prepare, transferring, terminate);
	signal spi_state	: fsm_type := idle;
	
	signal readoper	   : std_logic;
	signal writeoper	   : std_logic;
	signal spi_en        : std_logic;
	signal D_buff_msx	   : std_logic_vector(7 downto 0);
	signal D_buff_pi	   : std_logic_vector(7 downto 0);	
   
	signal RESET		: std_logic;
	signal spibitcount_s: integer range 0 to 8;
	signal D_buff_msx_r	: std_logic_vector(7 downto 0);
	signal MSXPIVer     : STD_LOGIC_VECTOR(3 DOWNTO 0) := "0111";
	signal wait_n_s     : std_logic := 'Z';
	signal start_fsm    : std_logic := '0';
	
begin

	LED <= start_fsm;
	SPI_CS <= not start_fsm;
    WAIT_n <= wait_n_s;
	
	readoper   <= not (IORQ_n or RD_n);
	writeoper  <= not (IORQ_n or WR_n);
	--spi_en     <= '1' when (writeoper = '1' and (A = CTRLPORT1 or A = DATAPORT1)) or
    --                        (readoper = '1' and A = DATAPORT1 and MSXPIVer(3) = '1') else '0';
	spi_en <= '1' when ((writeoper = '1' or readoper = '1') and A = DATAPORT1) else '0';
	
	
	--RESET <= '1' when writeoper = '1' and A = CTRLPORT1 and D = x"FF" else '0';
	--MSXPIVer <= D(3 downto 0) when writeoper = '1' and A = CTRLPORT2 else MSXPIVer;
	
	D_buff_msx <= D when writeoper = '1' and (A = CTRLPORT1 or A = DATAPORT1);

	D <= "0000000" & SPI_RDY when (readoper = '1' and A = CTRLPORT1) else  	
	     D_buff_pi when readoper = '1' and A = DATAPORT1 else
		  "0000" & MSXPIVer when (readoper = '1' and A = CTRLPORT2) else 
		  "ZZZZZZZZ";

    -- This process drives the /Wait signal on MSx
    -- Wait is driving '0' when MSX request an I/O to/from RPi,
    -- and driving 'Z' when RPi pulses the SPI_RDY signal.
    process(spi_en, SPI_RDY)
    begin
        if (SPI_RDY = '0') then
    	    start_fsm <= '0';
    		wait_n_s <= 'Z';
        elsif (rising_edge(spi_en)) then
    		wait_n_s <= '0';
    	    start_fsm <= '1';
    	 end if;
    end process;

    spi:process(SPI_SCLK,start_fsm)
    begin
    	if (start_fsm = '1' and spi_state = idle) then
    		spibitcount_s <= 0;
    		spi_state <= prepare;
    	elsif rising_edge(SPI_SCLK) then
    		case spi_state is
    			when idle =>
    				spi_state <= idle;
    			when prepare  =>
    				D_buff_msx_r <= D_buff_msx;
    				spi_state <= transferring;
    			when transferring =>
    				D_buff_pi <= D_buff_pi(6 downto 0) & SPI_MISO;
    				SPI_MOSI <= D_buff_msx_r(7);
    				D_buff_msx_r(7 downto 1) <= D_buff_msx_r(6 downto 0);
    				spibitcount_s <= spibitcount_s + 1;
    				if spibitcount_s > 6 then
    				    spi_state <= terminate;
    				end if;
    			when terminate =>
    			    spi_state <= idle;
    		end case;
    	end if;
    	
    end process;
end rtl;

