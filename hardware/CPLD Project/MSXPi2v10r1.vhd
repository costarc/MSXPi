-- Copyright (C) 1991-2013 Altera Corporation
-- Your use of Altera Corporation's design tools, logic functions 
-- and other software and tools, and its AMPP partner logic 
-- functions, and any output files from any of the foregoing 
-- (including device programming or simulation files), and any 
-- associated documentation or information are expressly subject 
-- to the terms and conditions of the Altera Program License 
-- Subscription Agreement, Altera MegaCore Function License 
-- Agreement, or other applicable license agreement, including, 
-- without limitation, that your use is for the sole purpose of 
-- programming logic devices manufactured by Altera and sold by 
-- Altera or its authorized distributors.  Please refer to the 
-- applicable agreement for further details.

library ieee;
use ieee.std_logic_1164.all;
library altera;
use altera.altera_syn_attributes.all;

entity MSXPi2v10r1 is
	port
	(
-- {ALTERA_IO_BEGIN} DO NOT REMOVE THIS LINE!

      GPIO : INOUT STD_LOGIC_VECTOR(27 DOWNTO 0);
		D : INOUT STD_LOGIC_VECTOR(7 DOWNTO 0);
		A : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		RD_N : in std_logic;
		WR_N : in std_logic;
		MREQ_N : in std_logic;
		BDIR_N : out std_logic;
		IORQ_N : in std_logic;
		M1_N : in std_logic;
		SLTSL_N : out std_logic;
		WAIT_N : out std_logic

-- {ALTERA_IO_END} DO NOT REMOVE THIS LINE!

	);

-- {ALTERA_ATTRIBUTE_BEGIN} DO NOT REMOVE THIS LINE!
-- {ALTERA_ATTRIBUTE_END} DO NOT REMOVE THIS LINE!
end MSXPi2v10r1;

library ieee;
use ieee.std_logic_1164.all;
package msxpi_package is
        constant MSXPIVer : STD_LOGIC_VECTOR(3 DOWNTO 0) := "1011";
        constant CTRLPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"56";
        constant CTRLPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"57";
        constant CTRLPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"58";
        constant CTRLPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"59";
        constant DATAPORT1: STD_LOGIC_VECTOR(7 downto 0) := x"5A";
        constant DATAPORT2: STD_LOGIC_VECTOR(7 downto 0) := x"5B";
        constant DATAPORT3: STD_LOGIC_VECTOR(7 downto 0) := x"5C";
        constant DATAPORT4: STD_LOGIC_VECTOR(7 downto 0) := x"5D";
		  constant MSXPIADDRESS: STD_LOGIC_VECTOR(15 downto 0) := x"CFFF";
end msxpi_package;

architecture ppl_type of MSXPi2v10r1 is

-- {ALTERA_COMPONENTS_BEGIN} DO NOT REMOVE THIS LINE!
-- {ALTERA_COMPONENTS_END} DO NOT REMOVE THIS LINE!

	signal msxpi_en : STD_LOGIC;
	signal msxpi_wait : STD_LOGIC;
	signal wait_n_s : STD_LOGIC;
	signal rpi_en_s : STD_LOGIC;
	signal rpi_ready_s : STD_LOGIC;
	signal rpi_read : STD_LOGIC;
	signal rpi_write : STD_LOGIC;
	signal rpi_busa : STD_LOGIC_VECTOR(15 DOWNTO 0);
	signal rpi_busd : STD_LOGIC_VECTOR(7 DOWNTO 0);

begin
-- {ALTERA_INSTANTIATION_BEGIN} DO NOT REMOVE THIS LINE!
-- {ALTERA_INSTANTIATION_END} DO NOT REMOVE THIS LINE!

   msxpi_wait <= '1' when A = x"CFFF" else 'Z';
   rpi_write <= '1' when msxpi_wait = '1' and WR_N = '0' else '0';
	rpi_read <= '1' when msxpi_wait = '1' and RD_N = '0' else '0';		 
	wait_n_s <= 'Z' when rpi_ready_s = '1' and (rpi_write = '1' or rpi_read = '1') else
	            '0' when rpi_write = '1' or rpi_read = '1' else 
					'Z';
				 
	D <= GPIO(7 DOWNTO 0) when rpi_read = '1' and rpi_ready_s = '1' else "ZZZZZZZZ";
	GPIO(7 DOWNTO 0) <= D when rpi_write = '1' else "ZZZZZZZZ";
	GPIO(8) <= not (rpi_write or rpi_read);
	rpi_ready_s <= not GPIO(9);
	WAIT_N <= wait_n_s;
	
end;


