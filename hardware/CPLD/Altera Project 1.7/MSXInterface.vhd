----------------------------------------------------------------------------------
-- Ronivon Candido Costa (c) 2016 / 2017
-- MSXPi v0.7 Rev.1 
—- Licensed under CERN OHL v. 1.2
------------------------------------------------------------------------------------ This documentation describes Open Hardware and is licensed under the 
-- CERN OHL v. 1.2. You may redistribute and modify this documentation 
-- under the terms of the CERN OHL v.1.2. (http://ohwr.org/cernohl). 
-- This documentation is distributed WITHOUT ANY EXPRESS OR IMPLIED
-- WARRANTY, INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND 
-- FITNESS FOR A PARTICULAR PURPOSE. Please see the CERN OHL v.1.2 
-- for applicable conditions
----------------------------------------------------------------------------------

library ieee ;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all;

ENTITY MSXInterface IS
PORT ( 
	D		: INOUT STD_LOGIC_VECTOR(7 DOWNTO 0);
	A		: IN STD_LOGIC_VECTOR(7 DOWNTO 0);
	IORQ_n		: IN STD_LOGIC;
	RD_n		: IN STD_LOGIC;
	WR_n		: IN STD_LOGIC;
	BUSDIR		: OUT STD_LOGIC;
	--
	SPI_CS		: OUT STD_LOGIC;
	SPI_SCLK	: IN STD_LOGIC;
	SPI_MOSI	: OUT STD_LOGIC;
	SPI_MISO	: IN STD_LOGIC;
	SPI_RDY  	: IN STD_LOGIC;
	--
	LED		: OUT STD_LOGIC
);
END MSXInterface;

architecture rtl of MSXInterface is
	type fsm_type is (idle, prepare, transferring);
	signal spi_state	: fsm_type := idle;
	
	signal readoper	   	: std_logic;
	signal writeoper	: std_logic;
	signal spi_en       	: std_logic;
	signal D_buff_msx	: std_logic_vector(7 downto 0);
	signal D_buff_pi	: std_logic_vector(7 downto 0);	
   
	signal RESET		: std_logic;
	signal spibitcount_s 	: integer range 0 to 8;
	signal D_buff_msx_r	: std_logic_vector(7 downto 0);
	signal SPI_en_s		: STD_LOGIC := '0';
	signal SPI_RDY_s	: STD_LOGIC;
	
begin

	LED <= not SPI_RDY_s;
	BUSDIR <= '0' when (readoper = '1' and (A = x"06" or A = x"07")) else '1';
	
	readoper   <= not (IORQ_n or RD_n);
	writeoper  <= not (IORQ_n or WR_n);
	spi_en     <= '1' when writeoper = '1' and (A = x"06" or A = x"07") else
					 '0';
	
	SPI_RDY_s <= SPI_en_s nor SPI_RDY;
	
	RESET <= '1' when writeoper = '1' and A = x"06" and D = x"FF" else '0';
	
	D_buff_msx <= D when writeoper = '1' and (A = x"06" or A = x"07");

	D <= "0000000" & SPI_RDY_s when (readoper = '1' and A = x"06") else  	
	     D_buff_pi when readoper = '1' and A = x"07" else
		  "ZZZZZZZZ";

    spi:process(SPI_SCLK,readoper,writeoper,RESET)
    begin
	if RESET = '1' then
		SPI_en_s <= '0';
		--V0.7.1?: SPI_en_s <= not SPI_RDY;
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

