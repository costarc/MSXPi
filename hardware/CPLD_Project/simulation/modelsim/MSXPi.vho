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

-- VENDOR "Altera"
-- PROGRAM "Quartus II 64-Bit"
-- VERSION "Version 13.0.1 Build 232 06/12/2013 Service Pack 1 SJ Web Edition"

-- DATE "10/05/2025 16:02:02"

-- 
-- Device: Altera EPM3064ALC44-10 Package PLCC44
-- 

-- 
-- This VHDL file should be used for ModelSim-Altera (VHDL) only
-- 

LIBRARY IEEE;
LIBRARY MAX;
USE IEEE.STD_LOGIC_1164.ALL;
USE MAX.MAX_COMPONENTS.ALL;

ENTITY 	MSXPi IS
    PORT (
	D : INOUT std_logic_vector(7 DOWNTO 0);
	A : IN std_logic_vector(7 DOWNTO 0);
	IORQ_n : IN std_logic;
	RD_n : IN std_logic;
	WR_n : IN std_logic;
	BUSDIR_n : OUT std_logic;
	WAIT_n : OUT std_logic;
	SPI_CS : OUT std_logic;
	SPI_SCLK : IN std_logic;
	SPI_MOSI : OUT std_logic;
	SPI_MISO : IN std_logic;
	SPI_RDY : IN std_logic
	);
END MSXPi;

-- Design Ports Information
-- A[0]	=>  Location: PIN_14
-- A[1]	=>  Location: PIN_34
-- A[2]	=>  Location: PIN_21
-- A[3]	=>  Location: PIN_25
-- A[4]	=>  Location: PIN_16
-- A[5]	=>  Location: PIN_33
-- A[6]	=>  Location: PIN_24
-- A[7]	=>  Location: PIN_12
-- IORQ_n	=>  Location: PIN_27
-- RD_n	=>  Location: PIN_26
-- WR_n	=>  Location: PIN_5
-- SPI_SCLK	=>  Location: PIN_8
-- SPI_MISO	=>  Location: PIN_4
-- SPI_RDY	=>  Location: PIN_40
-- D[0]	=>  Location: PIN_20
-- D[1]	=>  Location: PIN_37
-- D[2]	=>  Location: PIN_19
-- D[3]	=>  Location: PIN_39
-- D[4]	=>  Location: PIN_18
-- D[5]	=>  Location: PIN_41
-- D[6]	=>  Location: PIN_11
-- D[7]	=>  Location: PIN_29
-- WAIT_n	=>  Location: PIN_28
-- BUSDIR_n	=>  Location: PIN_31
-- SPI_CS	=>  Location: PIN_9
-- SPI_MOSI	=>  Location: PIN_6


ARCHITECTURE structure OF MSXPi IS
SIGNAL gnd : std_logic := '0';
SIGNAL vcc : std_logic := '1';
SIGNAL unknown : std_logic := 'X';
SIGNAL ww_A : std_logic_vector(7 DOWNTO 0);
SIGNAL ww_IORQ_n : std_logic;
SIGNAL ww_RD_n : std_logic;
SIGNAL ww_WR_n : std_logic;
SIGNAL ww_BUSDIR_n : std_logic;
SIGNAL ww_WAIT_n : std_logic;
SIGNAL ww_SPI_CS : std_logic;
SIGNAL ww_SPI_SCLK : std_logic;
SIGNAL ww_SPI_MOSI : std_logic;
SIGNAL ww_SPI_MISO : std_logic;
SIGNAL ww_SPI_RDY : std_logic;
SIGNAL \D[0]~43_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~43_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~46_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[1]~47_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[2]~53_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[3]~54_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[4]~60_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[5]~62_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[6]~64_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[7]~66_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \BUSDIR_n~4_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_en~1_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[1]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[2]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[0]~34_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[3]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[1]~38_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[4]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[2]~42_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[5]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[3]~46_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[6]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[4]~50_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[7]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[5]~54_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[6]~58_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx[7]~62_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[0]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[1]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spibitcount_s[2]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.idle_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_pterm0_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_pterm1_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_pterm2_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_pterm3_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_pterm4_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_pterm5_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_pxor_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_pclk_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_pena_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_paclr_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL SPI_en_s_papre_bus : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.prepare_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_en_s~16_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[0]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \SPI_MOSI~reg0_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \~VCC~0_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \RESET~3sexpbal_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_pterm0_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_pterm1_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_pterm2_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_pterm3_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_pterm4_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_pterm5_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_pxor_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_pclk_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_pena_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_paclr_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~37bal_papre_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~36_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~38_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]~25_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring~2_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \spi_state.transferring~3_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]~33_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]~34_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]~35_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]~36_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]~46_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]~47_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[2]~48_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]~58_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]~59_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[3]~60_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]~70_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]~71_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[4]~72_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]~82_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]~83_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[5]~84_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]~94_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]~95_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[6]~96_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]~106_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]~107_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[7]~108_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D~40sexp_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]~84_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]~85_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]~118_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_pi[0]~86_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D_buff_msx_r[1]~119_datain_bus\ : std_logic_vector(51 DOWNTO 0);
SIGNAL \D[0]~1\ : std_logic;
SIGNAL \D[1]~2\ : std_logic;
SIGNAL \D[2]~3\ : std_logic;
SIGNAL \D[3]~4\ : std_logic;
SIGNAL \D[4]~5\ : std_logic;
SIGNAL \D[5]~6\ : std_logic;
SIGNAL \D[6]~7\ : std_logic;
SIGNAL \D[7]~8\ : std_logic;
SIGNAL \SPI_SCLK~dataout\ : std_logic;
SIGNAL \IORQ_n~dataout\ : std_logic;
SIGNAL \WR_n~dataout\ : std_logic;
SIGNAL \spi_en~1_dataout\ : std_logic;
SIGNAL \RESET~3sexpbal_dataout\ : std_logic;
SIGNAL \spi_state.transferring~2_dataout\ : std_logic;
SIGNAL \spi_state.transferring~3_dataout\ : std_logic;
SIGNAL \spi_state.transferring~dataout\ : std_logic;
SIGNAL \spi_state.idle~dataout\ : std_logic;
SIGNAL \SPI_en_s~dataout\ : std_logic;
SIGNAL \SPI_RDY~dataout\ : std_logic;
SIGNAL \D[0]~37bal_dataout\ : std_logic;
SIGNAL \RD_n~dataout\ : std_logic;
SIGNAL \D[0]~38_dataout\ : std_logic;
SIGNAL \D[0]~36_dataout\ : std_logic;
SIGNAL \D[0]~43_dataout\ : std_logic;
SIGNAL \D[7]~46_dataout\ : std_logic;
SIGNAL \D_buff_pi[0]~25_dataout\ : std_logic;
SIGNAL \SPI_MISO~dataout\ : std_logic;
SIGNAL \D~40sexp_dataout\ : std_logic;
SIGNAL \D[1]~47_dataout\ : std_logic;
SIGNAL \D[2]~53_dataout\ : std_logic;
SIGNAL \D[3]~54_dataout\ : std_logic;
SIGNAL \D[4]~60_dataout\ : std_logic;
SIGNAL \D[5]~62_dataout\ : std_logic;
SIGNAL \D[6]~64_dataout\ : std_logic;
SIGNAL \D[7]~66_dataout\ : std_logic;
SIGNAL \~VCC~0~dataout\ : std_logic;
SIGNAL \BUSDIR_n~4_dataout\ : std_logic;
SIGNAL \SPI_en_s~16_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[7]~106_dataout\ : std_logic;
SIGNAL \D_buff_msx[7]~62_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[7]~107_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[7]~108_dataout\ : std_logic;
SIGNAL \D_buff_pi[0]~86_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[6]~94_dataout\ : std_logic;
SIGNAL \D_buff_msx[6]~58_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[6]~95_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[6]~96_dataout\ : std_logic;
SIGNAL \D_buff_pi[0]~85_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[5]~82_dataout\ : std_logic;
SIGNAL \D_buff_msx[5]~54_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[5]~83_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[5]~84_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[4]~70_dataout\ : std_logic;
SIGNAL \D_buff_msx[4]~50_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[4]~71_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[4]~72_dataout\ : std_logic;
SIGNAL \D_buff_pi[0]~84_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[3]~58_dataout\ : std_logic;
SIGNAL \D_buff_msx[3]~46_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[3]~59_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[3]~60_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[2]~46_dataout\ : std_logic;
SIGNAL \D_buff_msx[2]~42_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[2]~47_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[2]~48_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[1]~34_dataout\ : std_logic;
SIGNAL \D_buff_msx[1]~38_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[1]~35_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[1]~36_dataout\ : std_logic;
SIGNAL \D_buff_msx[0]~34_dataout\ : std_logic;
SIGNAL \spi_state.prepare~dataout\ : std_logic;
SIGNAL \D_buff_msx_r[1]~33_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[1]~118_dataout\ : std_logic;
SIGNAL \D_buff_msx_r[1]~119_dataout\ : std_logic;
SIGNAL \SPI_MOSI~reg0_dataout\ : std_logic;
SIGNAL spibitcount_s : std_logic_vector(2 DOWNTO 0);
SIGNAL D_buff_pi : std_logic_vector(7 DOWNTO 0);
SIGNAL D_buff_msx_r : std_logic_vector(7 DOWNTO 0);
SIGNAL \A~dataout\ : std_logic_vector(7 DOWNTO 0);
SIGNAL \ALT_INV_WR_n~dataout\ : std_logic;
SIGNAL \ALT_INV_RD_n~dataout\ : std_logic;
SIGNAL \ALT_INV_IORQ_n~dataout\ : std_logic;
SIGNAL \ALT_INV_A~dataout\ : std_logic_vector(7 DOWNTO 0);
SIGNAL \ALT_INV_SPI_MOSI~reg0_dataout\ : std_logic;
SIGNAL ALT_INV_D_buff_msx_r : std_logic_vector(7 DOWNTO 0);
SIGNAL \ALT_INV_spi_state.idle~dataout\ : std_logic;
SIGNAL \ALT_INV_SPI_en_s~dataout\ : std_logic;
SIGNAL \ALT_INV_D_buff_msx[7]~62_dataout\ : std_logic;
SIGNAL \ALT_INV_spi_state.transferring~dataout\ : std_logic;
SIGNAL \ALT_INV_D_buff_msx[6]~58_dataout\ : std_logic;
SIGNAL \ALT_INV_D_buff_msx[5]~54_dataout\ : std_logic;
SIGNAL \ALT_INV_D_buff_msx[4]~50_dataout\ : std_logic;
SIGNAL \ALT_INV_D_buff_msx[3]~46_dataout\ : std_logic;
SIGNAL \ALT_INV_D_buff_msx[2]~42_dataout\ : std_logic;
SIGNAL \ALT_INV_D_buff_msx[1]~38_dataout\ : std_logic;
SIGNAL \ALT_INV_D_buff_msx[0]~34_dataout\ : std_logic;
SIGNAL ALT_INV_D_buff_pi : std_logic_vector(0 DOWNTO 0);
SIGNAL \ALT_INV_spi_en~1_dataout\ : std_logic;

BEGIN

ww_A <= A;
ww_IORQ_n <= IORQ_n;
ww_RD_n <= RD_n;
ww_WR_n <= WR_n;
BUSDIR_n <= ww_BUSDIR_n;
WAIT_n <= ww_WAIT_n;
SPI_CS <= ww_SPI_CS;
ww_SPI_SCLK <= SPI_SCLK;
SPI_MOSI <= ww_SPI_MOSI;
ww_SPI_MISO <= SPI_MISO;
ww_SPI_RDY <= SPI_RDY;

\D[0]~43_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~43_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~37bal_dataout\);

\D[0]~43_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D[0]~36_dataout\ & \D[0]~38_dataout\);

\D[0]~43_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~43_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~43_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~43_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~43_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~43_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[0]~43_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~43_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~46_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~46_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0));

\D[7]~46_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2));

\D[7]~46_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~46_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~46_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~46_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~46_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~46_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[7]~46_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~46_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[1]~47_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[1]~47_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[1]~47_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(1));

\D[1]~47_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D~40sexp_dataout\);

\D[1]~47_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[1]~47_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[1]~47_pxor_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0));

\D[1]~47_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[1]~47_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[1]~47_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[1]~47_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[2]~53_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[2]~53_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0) & D_buff_pi(2));

\D[2]~53_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[2]~53_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[2]~53_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[2]~53_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[2]~53_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[2]~53_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[2]~53_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[2]~53_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[2]~53_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[3]~54_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[3]~54_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[3]~54_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(3));

\D[3]~54_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D~40sexp_dataout\);

\D[3]~54_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[3]~54_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[3]~54_pxor_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0));

\D[3]~54_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[3]~54_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[3]~54_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[3]~54_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[4]~60_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[4]~60_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0) & D_buff_pi(4));

\D[4]~60_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[4]~60_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[4]~60_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[4]~60_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[4]~60_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[4]~60_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[4]~60_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[4]~60_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[4]~60_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[5]~62_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[5]~62_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0) & D_buff_pi(5));

\D[5]~62_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[5]~62_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[5]~62_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[5]~62_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[5]~62_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[5]~62_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[5]~62_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[5]~62_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[5]~62_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[6]~64_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[6]~64_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0) & D_buff_pi(6));

\D[6]~64_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[6]~64_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[6]~64_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[6]~64_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[6]~64_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[6]~64_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[6]~64_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[6]~64_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[6]~64_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~66_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~66_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0) & D_buff_pi(7));

\D[7]~66_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~66_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~66_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~66_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~66_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~66_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~66_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[7]~66_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[7]~66_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\BUSDIR_n~4_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\BUSDIR_n~4_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0) & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\);

\BUSDIR_n~4_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\);

\BUSDIR_n~4_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\BUSDIR_n~4_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\BUSDIR_n~4_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\BUSDIR_n~4_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\BUSDIR_n~4_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\BUSDIR_n~4_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\BUSDIR_n~4_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\BUSDIR_n~4_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_en~1_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_en~1_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0) & NOT \WR_n~dataout\ & NOT \IORQ_n~dataout\);

\spi_en~1_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & NOT \WR_n~dataout\ & NOT \IORQ_n~dataout\);

\spi_en~1_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_en~1_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_en~1_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_en~1_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_en~1_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_en~1_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\spi_en~1_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_en~1_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[0]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_MISO~dataout\ & \D_buff_pi[0]~25_dataout\ & \spi_state.transferring~dataout\);

\D_buff_pi[0]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(0) & NOT \spi_state.transferring~dataout\);

\D_buff_pi[0]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[0]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[0]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\ & D_buff_pi(0));

\D_buff_pi[0]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[0]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[0]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_pi[0]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_pi[0]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\ & 
NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & \D[5]~6\
& \D[6]~7\ & \D[7]~8\);

\D_buff_pi[0]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[1]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(0) & \D_buff_pi[0]~25_dataout\ & \spi_state.transferring~dataout\);

\D_buff_pi[1]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(1) & NOT \spi_state.transferring~dataout\);

\D_buff_pi[1]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[1]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[1]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\ & D_buff_pi(1));

\D_buff_pi[1]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[1]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[1]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_pi[1]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_pi[1]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\ & 
NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & \D[5]~6\
& \D[6]~7\ & \D[7]~8\);

\D_buff_pi[1]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[2]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(1) & \D_buff_pi[0]~25_dataout\ & \spi_state.transferring~dataout\);

\D_buff_pi[2]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(2) & NOT \spi_state.transferring~dataout\);

\D_buff_pi[2]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[2]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[2]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\ & D_buff_pi(2));

\D_buff_pi[2]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[2]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[2]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_pi[2]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_pi[2]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\ & 
NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & \D[5]~6\
& \D[6]~7\ & \D[7]~8\);

\D_buff_pi[2]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[0]~34_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[0]~34_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & \D[0]~1\);

\D_buff_msx[0]~34_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[0]~34_dataout\ & NOT \spi_en~1_dataout\);

\D_buff_msx[0]~34_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[0]~34_dataout\ & \D[0]~1\);

\D_buff_msx[0]~34_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[0]~34_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[0]~34_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[0]~34_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[0]~34_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx[0]~34_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[0]~34_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[3]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(2) & \D_buff_pi[0]~25_dataout\ & \spi_state.transferring~dataout\);

\D_buff_pi[3]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(3) & NOT \spi_state.transferring~dataout\);

\D_buff_pi[3]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[3]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[3]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\ & D_buff_pi(3));

\D_buff_pi[3]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[3]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[3]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_pi[3]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_pi[3]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\ & 
NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & \D[5]~6\
& \D[6]~7\ & \D[7]~8\);

\D_buff_pi[3]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[1]~38_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[1]~38_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & \D[1]~2\);

\D_buff_msx[1]~38_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[1]~38_dataout\ & NOT \spi_en~1_dataout\);

\D_buff_msx[1]~38_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[1]~38_dataout\ & \D[1]~2\);

\D_buff_msx[1]~38_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[1]~38_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[1]~38_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[1]~38_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[1]~38_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx[1]~38_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[1]~38_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[4]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(3) & \D_buff_pi[0]~25_dataout\ & \spi_state.transferring~dataout\);

\D_buff_pi[4]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(4) & NOT \spi_state.transferring~dataout\);

\D_buff_pi[4]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[4]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[4]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\ & D_buff_pi(4));

\D_buff_pi[4]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[4]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[4]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_pi[4]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_pi[4]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\ & 
NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & \D[5]~6\
& \D[6]~7\ & \D[7]~8\);

\D_buff_pi[4]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[2]~42_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[2]~42_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & \D[2]~3\);

\D_buff_msx[2]~42_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[2]~42_dataout\ & NOT \spi_en~1_dataout\);

\D_buff_msx[2]~42_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[2]~42_dataout\ & \D[2]~3\);

\D_buff_msx[2]~42_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[2]~42_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[2]~42_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[2]~42_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[2]~42_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx[2]~42_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[2]~42_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[5]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(4) & \D_buff_pi[0]~25_dataout\ & \spi_state.transferring~dataout\);

\D_buff_pi[5]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(5) & NOT \spi_state.transferring~dataout\);

\D_buff_pi[5]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[5]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[5]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\ & D_buff_pi(5));

\D_buff_pi[5]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[5]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[5]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_pi[5]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_pi[5]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\ & 
NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & \D[5]~6\
& \D[6]~7\ & \D[7]~8\);

\D_buff_pi[5]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[3]~46_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[3]~46_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & \D[3]~4\);

\D_buff_msx[3]~46_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[3]~46_dataout\ & NOT \spi_en~1_dataout\);

\D_buff_msx[3]~46_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[3]~46_dataout\ & \D[3]~4\);

\D_buff_msx[3]~46_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[3]~46_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[3]~46_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[3]~46_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[3]~46_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx[3]~46_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[3]~46_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[6]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(5) & \D_buff_pi[0]~25_dataout\ & \spi_state.transferring~dataout\);

\D_buff_pi[6]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(6) & NOT \spi_state.transferring~dataout\);

\D_buff_pi[6]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[6]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[6]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\ & D_buff_pi(6));

\D_buff_pi[6]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[6]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[6]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_pi[6]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_pi[6]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\ & 
NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & \D[5]~6\
& \D[6]~7\ & \D[7]~8\);

\D_buff_pi[6]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[4]~50_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[4]~50_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & \D[4]~5\);

\D_buff_msx[4]~50_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[4]~50_dataout\ & NOT \spi_en~1_dataout\);

\D_buff_msx[4]~50_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[4]~50_dataout\ & \D[4]~5\);

\D_buff_msx[4]~50_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[4]~50_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[4]~50_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[4]~50_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[4]~50_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx[4]~50_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[4]~50_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[7]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(6) & \D_buff_pi[0]~25_dataout\ & \spi_state.transferring~dataout\);

\D_buff_pi[7]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & D_buff_pi(7) & NOT \spi_state.transferring~dataout\);

\D_buff_pi[7]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[7]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[7]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\ & D_buff_pi(7));

\D_buff_pi[7]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[7]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_pi[7]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_pi[7]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_pi[7]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\ & 
NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & \D[5]~6\
& \D[6]~7\ & \D[7]~8\);

\D_buff_pi[7]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[5]~54_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[5]~54_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & \D[5]~6\);

\D_buff_msx[5]~54_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[5]~54_dataout\ & NOT \spi_en~1_dataout\);

\D_buff_msx[5]~54_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[5]~54_dataout\ & \D[5]~6\);

\D_buff_msx[5]~54_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[5]~54_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[5]~54_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[5]~54_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[5]~54_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx[5]~54_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[5]~54_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[6]~58_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[6]~58_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & \D[6]~7\);

\D_buff_msx[6]~58_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[6]~58_dataout\ & NOT \spi_en~1_dataout\);

\D_buff_msx[6]~58_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[6]~58_dataout\ & \D[6]~7\);

\D_buff_msx[6]~58_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[6]~58_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[6]~58_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[6]~58_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[6]~58_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx[6]~58_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[6]~58_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.transferring_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.transferring_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \spi_state.transferring~dataout\ & \spi_state.idle~dataout\);

\spi_state.transferring_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.transferring_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.transferring_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & spibitcount_s(0) & spibitcount_s(1) & spibitcount_s(2) & \spi_state.transferring~dataout\);

\spi_state.transferring_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.transferring_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.transferring_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\spi_state.transferring_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\spi_state.transferring_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_state.transferring~3_dataout\ & \spi_state.transferring~2_dataout\);

\spi_state.transferring_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[7]~62_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[7]~62_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & \D[7]~8\);

\D_buff_msx[7]~62_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[7]~62_dataout\ & NOT \spi_en~1_dataout\);

\D_buff_msx[7]~62_pterm3_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx[7]~62_dataout\ & \D[7]~8\);

\D_buff_msx[7]~62_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[7]~62_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[7]~62_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[7]~62_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[7]~62_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx[7]~62_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx[7]~62_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[0]_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[0]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_state.transferring~dataout\);

\spibitcount_s[0]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[0]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[0]_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[0]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[0]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[0]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\spibitcount_s[0]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\spibitcount_s[0]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\spibitcount_s[0]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[1]_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[1]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & spibitcount_s(0) & \spi_state.transferring~dataout\);

\spibitcount_s[1]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[1]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[1]_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[1]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[1]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[1]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\spibitcount_s[1]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\spibitcount_s[1]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\spibitcount_s[1]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[2]_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[2]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & spibitcount_s(0) & \spi_state.transferring~dataout\ & spibitcount_s(1));

\spibitcount_s[2]_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[2]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[2]_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[2]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[2]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spibitcount_s[2]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\spibitcount_s[2]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\spibitcount_s[2]_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\spibitcount_s[2]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.idle_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.idle_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \spi_state.idle~dataout\ & spibitcount_s(0) & spibitcount_s(1) & spibitcount_s(2) & \spi_state.transferring~dataout\);

\spi_state.idle_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.idle_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.idle_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.idle_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.idle_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.idle_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\spi_state.idle_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\spi_state.idle_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\spi_state.idle_papre_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\
& NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & 
\D[5]~6\ & \D[6]~7\ & \D[7]~8\);

SPI_en_s_pterm0_bus <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

SPI_en_s_pterm1_bus <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \spi_state.idle~dataout\ & \SPI_en_s~dataout\);

SPI_en_s_pterm2_bus <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

SPI_en_s_pterm3_bus <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

SPI_en_s_pterm4_bus <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

SPI_en_s_pterm5_bus <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

SPI_en_s_pxor_bus <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

SPI_en_s_pclk_bus <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

SPI_en_s_pena_bus <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

SPI_en_s_paclr_bus <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\ & NOT 
\IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & \D[5]~6\ & 
\D[6]~7\ & \D[7]~8\);

SPI_en_s_papre_bus <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\spi_state.prepare_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \spi_state.transferring~dataout\ & \spi_state.prepare~dataout\ & NOT \spi_state.idle~dataout\);

\spi_state.prepare_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_state.prepare~dataout\ & NOT \spi_state.idle~dataout\ & spibitcount_s(0) & spibitcount_s(1) & spibitcount_s(2));

\spi_state.prepare_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.prepare_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.prepare_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.prepare_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.prepare_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\spi_state.prepare_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\spi_state.prepare_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\spi_state.prepare_paclr_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT 
\WR_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & 
\D[4]~5\ & \D[5]~6\ & \D[6]~7\ & \D[7]~8\);

\spi_state.prepare_papre_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\SPI_en_s~16_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_en_s~16_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_en_s~dataout\);

\SPI_en_s~16_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_en_s~16_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_en_s~16_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_en_s~16_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_en_s~16_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_en_s~16_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_en_s~16_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\SPI_en_s~16_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_en_s~16_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[0]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \spi_en~1_dataout\ & D_buff_msx_r(0) & \spi_state.prepare~dataout\ & NOT \D_buff_msx[0]~34_dataout\);

\D_buff_msx_r[0]_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT D_buff_msx_r(0) & \spi_state.prepare~dataout\ & \D_buff_msx[0]~34_dataout\ & \SPI_en_s~dataout\);

\D_buff_msx_r[0]_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \spi_en~1_dataout\ & NOT D_buff_msx_r(0) & \spi_state.prepare~dataout\ & \D_buff_msx[0]~34_dataout\);

\D_buff_msx_r[0]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[0]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & D_buff_msx_r(0) & \spi_state.prepare~dataout\ & NOT \D_buff_msx[0]~34_dataout\ & \SPI_en_s~dataout\);

\D_buff_msx_r[0]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[0]_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[0]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_msx_r[0]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx_r[0]_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[0]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[1]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(1) & \D_buff_msx_r[1]~33_dataout\ & \D_buff_msx_r[1]~36_dataout\ & \D_buff_msx_r[1]~35_dataout\ & \D_buff_msx_r[1]~34_dataout\);

\D_buff_msx_r[1]_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[1]_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & NOT D_buff_msx_r(0) & \D_buff_pi[0]~84_dataout\ & \D_buff_msx_r[1]~36_dataout\ & \D_buff_msx_r[1]~35_dataout\ & 
\D_buff_msx_r[1]~34_dataout\);

\D_buff_msx_r[1]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[1]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \D_buff_msx[1]~38_dataout\ & NOT \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & \D_buff_pi[0]~84_dataout\ & \D_buff_msx_r[1]~36_dataout\ & 
\D_buff_msx_r[1]~35_dataout\ & \D_buff_msx_r[1]~34_dataout\);

\D_buff_msx_r[1]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[1]_pxor_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx_r[1]~36_dataout\ & \D_buff_msx_r[1]~35_dataout\ & \D_buff_msx_r[1]~34_dataout\);

\D_buff_msx_r[1]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_msx_r[1]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx_r[1]_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[1]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[2]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(2) & \D_buff_msx_r[1]~33_dataout\ & \D_buff_msx_r[2]~48_dataout\ & \D_buff_msx_r[2]~47_dataout\ & \D_buff_msx_r[2]~46_dataout\);

\D_buff_msx_r[2]_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[2]_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & NOT D_buff_msx_r(1) & \D_buff_pi[0]~84_dataout\ & \D_buff_msx_r[2]~48_dataout\ & \D_buff_msx_r[2]~47_dataout\ & 
\D_buff_msx_r[2]~46_dataout\);

\D_buff_msx_r[2]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[2]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \D_buff_msx[2]~42_dataout\ & NOT \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & \D_buff_pi[0]~84_dataout\ & \D_buff_msx_r[2]~48_dataout\ & 
\D_buff_msx_r[2]~47_dataout\ & \D_buff_msx_r[2]~46_dataout\);

\D_buff_msx_r[2]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[2]_pxor_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx_r[2]~48_dataout\ & \D_buff_msx_r[2]~47_dataout\ & \D_buff_msx_r[2]~46_dataout\);

\D_buff_msx_r[2]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_msx_r[2]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx_r[2]_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[2]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[3]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(3) & \D_buff_msx_r[1]~118_dataout\ & \D_buff_msx_r[3]~60_dataout\ & \D_buff_msx_r[3]~59_dataout\ & \D_buff_msx_r[3]~58_dataout\);

\D_buff_msx_r[3]_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[3]_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & NOT D_buff_msx_r(2) & \D_buff_pi[0]~85_dataout\ & \D_buff_msx_r[3]~60_dataout\ & \D_buff_msx_r[3]~59_dataout\ & 
\D_buff_msx_r[3]~58_dataout\);

\D_buff_msx_r[3]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[3]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \D_buff_msx[3]~46_dataout\ & NOT \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & \D_buff_pi[0]~85_dataout\ & \D_buff_msx_r[3]~60_dataout\ & 
\D_buff_msx_r[3]~59_dataout\ & \D_buff_msx_r[3]~58_dataout\);

\D_buff_msx_r[3]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[3]_pxor_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx_r[3]~60_dataout\ & \D_buff_msx_r[3]~59_dataout\ & \D_buff_msx_r[3]~58_dataout\);

\D_buff_msx_r[3]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_msx_r[3]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx_r[3]_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[3]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[4]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(4) & \D_buff_msx_r[1]~33_dataout\ & \D_buff_msx_r[4]~72_dataout\ & \D_buff_msx_r[4]~71_dataout\ & \D_buff_msx_r[4]~70_dataout\);

\D_buff_msx_r[4]_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[4]_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & NOT D_buff_msx_r(3) & \D_buff_pi[0]~84_dataout\ & \D_buff_msx_r[4]~72_dataout\ & \D_buff_msx_r[4]~71_dataout\ & 
\D_buff_msx_r[4]~70_dataout\);

\D_buff_msx_r[4]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[4]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \D_buff_msx[4]~50_dataout\ & NOT \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & \D_buff_pi[0]~84_dataout\ & \D_buff_msx_r[4]~72_dataout\ & 
\D_buff_msx_r[4]~71_dataout\ & \D_buff_msx_r[4]~70_dataout\);

\D_buff_msx_r[4]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[4]_pxor_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx_r[4]~72_dataout\ & \D_buff_msx_r[4]~71_dataout\ & \D_buff_msx_r[4]~70_dataout\);

\D_buff_msx_r[4]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_msx_r[4]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx_r[4]_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[4]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[5]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(5) & \D_buff_msx_r[1]~118_dataout\ & \D_buff_msx_r[5]~84_dataout\ & \D_buff_msx_r[5]~83_dataout\ & \D_buff_msx_r[5]~82_dataout\);

\D_buff_msx_r[5]_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[5]_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & NOT D_buff_msx_r(4) & \D_buff_pi[0]~85_dataout\ & \D_buff_msx_r[5]~84_dataout\ & \D_buff_msx_r[5]~83_dataout\ & 
\D_buff_msx_r[5]~82_dataout\);

\D_buff_msx_r[5]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[5]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \D_buff_msx[5]~54_dataout\ & NOT \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & \D_buff_pi[0]~85_dataout\ & \D_buff_msx_r[5]~84_dataout\ & 
\D_buff_msx_r[5]~83_dataout\ & \D_buff_msx_r[5]~82_dataout\);

\D_buff_msx_r[5]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[5]_pxor_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx_r[5]~84_dataout\ & \D_buff_msx_r[5]~83_dataout\ & \D_buff_msx_r[5]~82_dataout\);

\D_buff_msx_r[5]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_msx_r[5]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx_r[5]_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[5]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[6]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(6) & \D_buff_msx_r[1]~118_dataout\ & \D_buff_msx_r[6]~96_dataout\ & \D_buff_msx_r[6]~95_dataout\ & \D_buff_msx_r[6]~94_dataout\);

\D_buff_msx_r[6]_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[6]_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & NOT D_buff_msx_r(5) & \D_buff_pi[0]~85_dataout\ & \D_buff_msx_r[6]~96_dataout\ & \D_buff_msx_r[6]~95_dataout\ & 
\D_buff_msx_r[6]~94_dataout\);

\D_buff_msx_r[6]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[6]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \D_buff_msx[6]~58_dataout\ & NOT \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & \D_buff_pi[0]~85_dataout\ & \D_buff_msx_r[6]~96_dataout\ & 
\D_buff_msx_r[6]~95_dataout\ & \D_buff_msx_r[6]~94_dataout\);

\D_buff_msx_r[6]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[6]_pxor_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx_r[6]~96_dataout\ & \D_buff_msx_r[6]~95_dataout\ & \D_buff_msx_r[6]~94_dataout\);

\D_buff_msx_r[6]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_msx_r[6]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx_r[6]_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[6]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[7]_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(7) & \D_buff_msx_r[1]~119_dataout\ & \D_buff_msx_r[7]~108_dataout\ & \D_buff_msx_r[7]~107_dataout\ & \D_buff_msx_r[7]~106_dataout\);

\D_buff_msx_r[7]_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[7]_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & NOT D_buff_msx_r(6) & \D_buff_pi[0]~86_dataout\ & \D_buff_msx_r[7]~108_dataout\ & \D_buff_msx_r[7]~107_dataout\ & 
\D_buff_msx_r[7]~106_dataout\);

\D_buff_msx_r[7]_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[7]_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \D_buff_msx[7]~62_dataout\ & NOT \spi_state.transferring~dataout\ & NOT \spi_state.idle~dataout\ & \D_buff_pi[0]~86_dataout\ & \D_buff_msx_r[7]~108_dataout\ & 
\D_buff_msx_r[7]~107_dataout\ & \D_buff_msx_r[7]~106_dataout\);

\D_buff_msx_r[7]_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[7]_pxor_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \D_buff_msx_r[7]~108_dataout\ & \D_buff_msx_r[7]~107_dataout\ & \D_buff_msx_r[7]~106_dataout\);

\D_buff_msx_r[7]_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\D_buff_msx_r[7]_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D_buff_msx_r[7]_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D_buff_msx_r[7]_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_MOSI~reg0_pterm0_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \spi_en~1_dataout\ & \SPI_MOSI~reg0_dataout\ & \spi_state.transferring~dataout\ & NOT D_buff_msx_r(7));

\SPI_MOSI~reg0_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \SPI_MOSI~reg0_dataout\ & \spi_state.transferring~dataout\ & D_buff_msx_r(7) & \SPI_en_s~dataout\);

\SPI_MOSI~reg0_pterm2_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \spi_en~1_dataout\ & NOT \SPI_MOSI~reg0_dataout\ & \spi_state.transferring~dataout\ & D_buff_msx_r(7));

\SPI_MOSI~reg0_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_MOSI~reg0_pterm4_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \SPI_MOSI~reg0_dataout\ & \spi_state.transferring~dataout\ & NOT D_buff_msx_r(7) & \SPI_en_s~dataout\);

\SPI_MOSI~reg0_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_MOSI~reg0_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_MOSI~reg0_pclk_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_SCLK~dataout\);

\SPI_MOSI~reg0_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\SPI_MOSI~reg0_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\SPI_MOSI~reg0_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_pterm1_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\~VCC~0_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\~VCC~0_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\RESET~3sexpbal_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\RESET~3sexpbal_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT \WR_n~dataout\
& NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0) & \D[0]~1\ & \D[1]~2\ & \D[2]~3\ & \D[3]~4\ & \D[4]~5\ & 
\D[5]~6\ & \D[6]~7\ & \D[7]~8\);

\RESET~3sexpbal_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\RESET~3sexpbal_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\RESET~3sexpbal_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\RESET~3sexpbal_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\RESET~3sexpbal_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\RESET~3sexpbal_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\RESET~3sexpbal_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\RESET~3sexpbal_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\RESET~3sexpbal_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~37bal_pterm0_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~37bal_pterm1_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \SPI_RDY~dataout\ & NOT \SPI_en_s~dataout\);

\D[0]~37bal_pterm2_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~37bal_pterm3_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~37bal_pterm4_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~37bal_pterm5_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd
& gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~37bal_pxor_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~37bal_pclk_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~37bal_pena_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc);

\D[0]~37bal_paclr_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~37bal_papre_bus\ <= (gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & 
gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd & gnd);

\D[0]~36_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & NOT \A~dataout\(3) & \A~dataout\(2) & NOT \A~dataout\(0));

\D[0]~38_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0) & NOT D_buff_pi(0));

\D_buff_pi[0]~25_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\spi_state.transferring~2_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & \SPI_en_s~dataout\);

\spi_state.transferring~3_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \spi_en~1_dataout\);

\D_buff_msx_r[1]~33_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \spi_state.idle~dataout\);

\D_buff_msx_r[1]~34_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(1) & \spi_state.transferring~dataout\ & NOT D_buff_msx_r(0));

\D_buff_msx_r[1]~35_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(1) & NOT \D_buff_msx[1]~38_dataout\ & NOT \spi_state.transferring~dataout\);

\D_buff_msx_r[1]~36_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(1) & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D_buff_msx_r[2]~46_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(2) & \spi_state.transferring~dataout\ & NOT D_buff_msx_r(1));

\D_buff_msx_r[2]~47_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(2) & NOT \D_buff_msx[2]~42_dataout\ & NOT \spi_state.transferring~dataout\);

\D_buff_msx_r[2]~48_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(2) & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D_buff_msx_r[3]~58_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(3) & \spi_state.transferring~dataout\ & NOT D_buff_msx_r(2));

\D_buff_msx_r[3]~59_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(3) & NOT \D_buff_msx[3]~46_dataout\ & NOT \spi_state.transferring~dataout\);

\D_buff_msx_r[3]~60_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(3) & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D_buff_msx_r[4]~70_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(4) & \spi_state.transferring~dataout\ & NOT D_buff_msx_r(3));

\D_buff_msx_r[4]~71_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(4) & NOT \D_buff_msx[4]~50_dataout\ & NOT \spi_state.transferring~dataout\);

\D_buff_msx_r[4]~72_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(4) & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D_buff_msx_r[5]~82_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(5) & \spi_state.transferring~dataout\ & NOT D_buff_msx_r(4));

\D_buff_msx_r[5]~83_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(5) & NOT \D_buff_msx[5]~54_dataout\ & NOT \spi_state.transferring~dataout\);

\D_buff_msx_r[5]~84_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(5) & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D_buff_msx_r[6]~94_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(6) & \spi_state.transferring~dataout\ & NOT D_buff_msx_r(5));

\D_buff_msx_r[6]~95_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(6) & NOT \D_buff_msx[6]~58_dataout\ & NOT \spi_state.transferring~dataout\);

\D_buff_msx_r[6]~96_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc
& vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(6) & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D_buff_msx_r[7]~106_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(7) & \spi_state.transferring~dataout\ & NOT D_buff_msx_r(6));

\D_buff_msx_r[7]~107_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(7) & NOT \D_buff_msx[7]~62_dataout\ & NOT \spi_state.transferring~dataout\);

\D_buff_msx_r[7]~108_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & NOT D_buff_msx_r(7) & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D~40sexp_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & NOT \RD_n~dataout\ & NOT \IORQ_n~dataout\ & NOT \A~dataout\(7) & \A~dataout\(6) & NOT \A~dataout\(5) & \A~dataout\(4) & \A~dataout\(1) & \A~dataout\(3) & NOT \A~dataout\(2) & NOT \A~dataout\(0));

\D_buff_pi[0]~84_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D_buff_pi[0]~85_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D_buff_msx_r[1]~118_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \spi_state.idle~dataout\);

\D_buff_pi[0]~86_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \spi_en~1_dataout\ & NOT \SPI_en_s~dataout\);

\D_buff_msx_r[1]~119_datain_bus\ <= (vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & 
vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & vcc & \RESET~3sexpbal_dataout\ & NOT \spi_state.idle~dataout\);
\ALT_INV_WR_n~dataout\ <= NOT \WR_n~dataout\;
\ALT_INV_RD_n~dataout\ <= NOT \RD_n~dataout\;
\ALT_INV_IORQ_n~dataout\ <= NOT \IORQ_n~dataout\;
\ALT_INV_A~dataout\(7) <= NOT \A~dataout\(7);
\ALT_INV_A~dataout\(5) <= NOT \A~dataout\(5);
\ALT_INV_A~dataout\(3) <= NOT \A~dataout\(3);
\ALT_INV_A~dataout\(2) <= NOT \A~dataout\(2);
\ALT_INV_A~dataout\(0) <= NOT \A~dataout\(0);
\ALT_INV_SPI_MOSI~reg0_dataout\ <= NOT \SPI_MOSI~reg0_dataout\;
ALT_INV_D_buff_msx_r(7) <= NOT D_buff_msx_r(7);
ALT_INV_D_buff_msx_r(6) <= NOT D_buff_msx_r(6);
ALT_INV_D_buff_msx_r(5) <= NOT D_buff_msx_r(5);
ALT_INV_D_buff_msx_r(4) <= NOT D_buff_msx_r(4);
ALT_INV_D_buff_msx_r(3) <= NOT D_buff_msx_r(3);
ALT_INV_D_buff_msx_r(2) <= NOT D_buff_msx_r(2);
ALT_INV_D_buff_msx_r(1) <= NOT D_buff_msx_r(1);
ALT_INV_D_buff_msx_r(0) <= NOT D_buff_msx_r(0);
\ALT_INV_spi_state.idle~dataout\ <= NOT \spi_state.idle~dataout\;
\ALT_INV_SPI_en_s~dataout\ <= NOT \SPI_en_s~dataout\;
\ALT_INV_D_buff_msx[7]~62_dataout\ <= NOT \D_buff_msx[7]~62_dataout\;
\ALT_INV_spi_state.transferring~dataout\ <= NOT \spi_state.transferring~dataout\;
\ALT_INV_D_buff_msx[6]~58_dataout\ <= NOT \D_buff_msx[6]~58_dataout\;
\ALT_INV_D_buff_msx[5]~54_dataout\ <= NOT \D_buff_msx[5]~54_dataout\;
\ALT_INV_D_buff_msx[4]~50_dataout\ <= NOT \D_buff_msx[4]~50_dataout\;
\ALT_INV_D_buff_msx[3]~46_dataout\ <= NOT \D_buff_msx[3]~46_dataout\;
\ALT_INV_D_buff_msx[2]~42_dataout\ <= NOT \D_buff_msx[2]~42_dataout\;
\ALT_INV_D_buff_msx[1]~38_dataout\ <= NOT \D_buff_msx[1]~38_dataout\;
\ALT_INV_D_buff_msx[0]~34_dataout\ <= NOT \D_buff_msx[0]~34_dataout\;
ALT_INV_D_buff_pi(0) <= NOT D_buff_pi(0);
\ALT_INV_spi_en~1_dataout\ <= NOT \spi_en~1_dataout\;

-- Location: PIN_20
\D[0]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "bidir",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \D[0]~43_dataout\,
	oe => \D[7]~46_dataout\,
	padio => D(0),
	dataout => \D[0]~1\);

-- Location: PIN_37
\D[1]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "bidir",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \D[1]~47_dataout\,
	oe => \D[7]~46_dataout\,
	padio => D(1),
	dataout => \D[1]~2\);

-- Location: PIN_19
\D[2]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "bidir",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \D[2]~53_dataout\,
	oe => \D[7]~46_dataout\,
	padio => D(2),
	dataout => \D[2]~3\);

-- Location: PIN_39
\D[3]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "bidir",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \D[3]~54_dataout\,
	oe => \D[7]~46_dataout\,
	padio => D(3),
	dataout => \D[3]~4\);

-- Location: PIN_18
\D[4]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "bidir",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \D[4]~60_dataout\,
	oe => \D[7]~46_dataout\,
	padio => D(4),
	dataout => \D[4]~5\);

-- Location: PIN_41
\D[5]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "bidir",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \D[5]~62_dataout\,
	oe => \D[7]~46_dataout\,
	padio => D(5),
	dataout => \D[5]~6\);

-- Location: PIN_11
\D[6]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "bidir",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \D[6]~64_dataout\,
	oe => \D[7]~46_dataout\,
	padio => D(6),
	dataout => \D[6]~7\);

-- Location: PIN_29
\D[7]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "bidir",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \D[7]~66_dataout\,
	oe => \D[7]~46_dataout\,
	padio => D(7),
	dataout => \D[7]~8\);

-- Location: PIN_8
\SPI_SCLK~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_SPI_SCLK,
	dataout => \SPI_SCLK~dataout\);

-- Location: PIN_27
\IORQ_n~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_IORQ_n,
	dataout => \IORQ_n~dataout\);

-- Location: PIN_5
\WR_n~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_WR_n,
	dataout => \WR_n~dataout\);

-- Location: PIN_14
\A[0]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_A(0),
	dataout => \A~dataout\(0));

-- Location: PIN_21
\A[2]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_A(2),
	dataout => \A~dataout\(2));

-- Location: PIN_25
\A[3]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_A(3),
	dataout => \A~dataout\(3));

-- Location: PIN_34
\A[1]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_A(1),
	dataout => \A~dataout\(1));

-- Location: PIN_16
\A[4]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_A(4),
	dataout => \A~dataout\(4));

-- Location: PIN_33
\A[5]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_A(5),
	dataout => \A~dataout\(5));

-- Location: PIN_24
\A[6]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_A(6),
	dataout => \A~dataout\(6));

-- Location: PIN_12
\A[7]~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_A(7),
	dataout => \A~dataout\(7));

-- Location: LC39
\spi_en~1\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \spi_en~1_pterm0_bus\,
	pterm1 => \spi_en~1_pterm1_bus\,
	pterm2 => \spi_en~1_pterm2_bus\,
	pterm3 => \spi_en~1_pterm3_bus\,
	pterm4 => \spi_en~1_pterm4_bus\,
	pterm5 => \spi_en~1_pterm5_bus\,
	pxor => \spi_en~1_pxor_bus\,
	pclk => \spi_en~1_pclk_bus\,
	papre => \spi_en~1_papre_bus\,
	paclr => \spi_en~1_paclr_bus\,
	pena => \spi_en~1_pena_bus\,
	dataout => \spi_en~1_dataout\);

-- Location: LC12
\RESET~3sexpbal\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "invert",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \RESET~3sexpbal_pterm0_bus\,
	pterm1 => \RESET~3sexpbal_pterm1_bus\,
	pterm2 => \RESET~3sexpbal_pterm2_bus\,
	pterm3 => \RESET~3sexpbal_pterm3_bus\,
	pterm4 => \RESET~3sexpbal_pterm4_bus\,
	pterm5 => \RESET~3sexpbal_pterm5_bus\,
	pxor => \RESET~3sexpbal_pxor_bus\,
	pclk => \RESET~3sexpbal_pclk_bus\,
	papre => \RESET~3sexpbal_papre_bus\,
	paclr => \RESET~3sexpbal_paclr_bus\,
	pena => \RESET~3sexpbal_pena_bus\,
	dataout => \RESET~3sexpbal_dataout\);

-- Location: LC14
\spibitcount_s[0]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "tff")
-- pragma translate_on
PORT MAP (
	pterm0 => \spibitcount_s[0]_pterm0_bus\,
	pterm1 => \spibitcount_s[0]_pterm1_bus\,
	pterm2 => \spibitcount_s[0]_pterm2_bus\,
	pterm3 => \spibitcount_s[0]_pterm3_bus\,
	pterm4 => \spibitcount_s[0]_pterm4_bus\,
	pterm5 => \spibitcount_s[0]_pterm5_bus\,
	pxor => \spibitcount_s[0]_pxor_bus\,
	pclk => \spibitcount_s[0]_pclk_bus\,
	papre => \spibitcount_s[0]_papre_bus\,
	paclr => \spibitcount_s[0]_paclr_bus\,
	pena => \spibitcount_s[0]_pena_bus\,
	dataout => spibitcount_s(0));

-- Location: LC35
\spibitcount_s[1]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "tff")
-- pragma translate_on
PORT MAP (
	pterm0 => \spibitcount_s[1]_pterm0_bus\,
	pterm1 => \spibitcount_s[1]_pterm1_bus\,
	pterm2 => \spibitcount_s[1]_pterm2_bus\,
	pterm3 => \spibitcount_s[1]_pterm3_bus\,
	pterm4 => \spibitcount_s[1]_pterm4_bus\,
	pterm5 => \spibitcount_s[1]_pterm5_bus\,
	pxor => \spibitcount_s[1]_pxor_bus\,
	pclk => \spibitcount_s[1]_pclk_bus\,
	papre => \spibitcount_s[1]_papre_bus\,
	paclr => \spibitcount_s[1]_paclr_bus\,
	pena => \spibitcount_s[1]_pena_bus\,
	dataout => spibitcount_s(1));

-- Location: LC9
\spibitcount_s[2]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "tff")
-- pragma translate_on
PORT MAP (
	pterm0 => \spibitcount_s[2]_pterm0_bus\,
	pterm1 => \spibitcount_s[2]_pterm1_bus\,
	pterm2 => \spibitcount_s[2]_pterm2_bus\,
	pterm3 => \spibitcount_s[2]_pterm3_bus\,
	pterm4 => \spibitcount_s[2]_pterm4_bus\,
	pterm5 => \spibitcount_s[2]_pterm5_bus\,
	pxor => \spibitcount_s[2]_pxor_bus\,
	pclk => \spibitcount_s[2]_pclk_bus\,
	papre => \spibitcount_s[2]_papre_bus\,
	paclr => \spibitcount_s[2]_paclr_bus\,
	pena => \spibitcount_s[2]_pena_bus\,
	dataout => spibitcount_s(2));

-- Location: SEXP2
\spi_state.transferring~2\ : max_sexp
PORT MAP (
	datain => \spi_state.transferring~2_datain_bus\,
	dataout => \spi_state.transferring~2_dataout\);

-- Location: SEXP7
\spi_state.transferring~3\ : max_sexp
PORT MAP (
	datain => \spi_state.transferring~3_datain_bus\,
	dataout => \spi_state.transferring~3_dataout\);

-- Location: LC2
\spi_state.transferring\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "invert",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \spi_state.transferring_pterm0_bus\,
	pterm1 => \spi_state.transferring_pterm1_bus\,
	pterm2 => \spi_state.transferring_pterm2_bus\,
	pterm3 => \spi_state.transferring_pterm3_bus\,
	pterm4 => \spi_state.transferring_pterm4_bus\,
	pterm5 => \spi_state.transferring_pterm5_bus\,
	pxor => \spi_state.transferring_pxor_bus\,
	pclk => \spi_state.transferring_pclk_bus\,
	papre => \spi_state.transferring_papre_bus\,
	paclr => \spi_state.transferring_paclr_bus\,
	pena => \spi_state.transferring_pena_bus\,
	dataout => \spi_state.transferring~dataout\);

-- Location: LC8
\spi_state.idle\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "tff")
-- pragma translate_on
PORT MAP (
	pterm0 => \spi_state.idle_pterm0_bus\,
	pterm1 => \spi_state.idle_pterm1_bus\,
	pterm2 => \spi_state.idle_pterm2_bus\,
	pterm3 => \spi_state.idle_pterm3_bus\,
	pterm4 => \spi_state.idle_pterm4_bus\,
	pterm5 => \spi_state.idle_pterm5_bus\,
	pxor => \spi_state.idle_pxor_bus\,
	pclk => \spi_state.idle_pclk_bus\,
	papre => \spi_state.idle_papre_bus\,
	paclr => \spi_state.idle_paclr_bus\,
	pena => \spi_state.idle_pena_bus\,
	dataout => \spi_state.idle~dataout\);

-- Location: LC7
SPI_en_s : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => SPI_en_s_pterm0_bus,
	pterm1 => SPI_en_s_pterm1_bus,
	pterm2 => SPI_en_s_pterm2_bus,
	pterm3 => SPI_en_s_pterm3_bus,
	pterm4 => SPI_en_s_pterm4_bus,
	pterm5 => SPI_en_s_pterm5_bus,
	pxor => SPI_en_s_pxor_bus,
	pclk => SPI_en_s_pclk_bus,
	papre => SPI_en_s_papre_bus,
	paclr => SPI_en_s_paclr_bus,
	pena => SPI_en_s_pena_bus,
	dataout => \SPI_en_s~dataout\);

-- Location: PIN_40
\SPI_RDY~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_SPI_RDY,
	dataout => \SPI_RDY~dataout\);

-- Location: LC48
\D[0]~37bal\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "invert",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[0]~37bal_pterm0_bus\,
	pterm1 => \D[0]~37bal_pterm1_bus\,
	pterm2 => \D[0]~37bal_pterm2_bus\,
	pterm3 => \D[0]~37bal_pterm3_bus\,
	pterm4 => \D[0]~37bal_pterm4_bus\,
	pterm5 => \D[0]~37bal_pterm5_bus\,
	pxor => \D[0]~37bal_pxor_bus\,
	pclk => \D[0]~37bal_pclk_bus\,
	papre => \D[0]~37bal_papre_bus\,
	paclr => \D[0]~37bal_paclr_bus\,
	pena => \D[0]~37bal_pena_bus\,
	dataout => \D[0]~37bal_dataout\);

-- Location: PIN_26
\RD_n~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_RD_n,
	dataout => \RD_n~dataout\);

-- Location: SEXP20
\D[0]~38\ : max_sexp
PORT MAP (
	datain => \D[0]~38_datain_bus\,
	dataout => \D[0]~38_dataout\);

-- Location: SEXP19
\D[0]~36\ : max_sexp
PORT MAP (
	datain => \D[0]~36_datain_bus\,
	dataout => \D[0]~36_dataout\);

-- Location: LC19
\D[0]~43\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[0]~43_pterm0_bus\,
	pterm1 => \D[0]~43_pterm1_bus\,
	pterm2 => \D[0]~43_pterm2_bus\,
	pterm3 => \D[0]~43_pterm3_bus\,
	pterm4 => \D[0]~43_pterm4_bus\,
	pterm5 => \D[0]~43_pterm5_bus\,
	pxor => \D[0]~43_pxor_bus\,
	pclk => \D[0]~43_pclk_bus\,
	papre => \D[0]~43_papre_bus\,
	paclr => \D[0]~43_paclr_bus\,
	pena => \D[0]~43_pena_bus\,
	dataout => \D[0]~43_dataout\);

-- Location: LC33
\D[7]~46\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[7]~46_pterm0_bus\,
	pterm1 => \D[7]~46_pterm1_bus\,
	pterm2 => \D[7]~46_pterm2_bus\,
	pterm3 => \D[7]~46_pterm3_bus\,
	pterm4 => \D[7]~46_pterm4_bus\,
	pterm5 => \D[7]~46_pterm5_bus\,
	pxor => \D[7]~46_pxor_bus\,
	pclk => \D[7]~46_pclk_bus\,
	papre => \D[7]~46_papre_bus\,
	paclr => \D[7]~46_paclr_bus\,
	pena => \D[7]~46_pena_bus\,
	dataout => \D[7]~46_dataout\);

-- Location: SEXP21
\D_buff_pi[0]~25\ : max_sexp
PORT MAP (
	datain => \D_buff_pi[0]~25_datain_bus\,
	dataout => \D_buff_pi[0]~25_dataout\);

-- Location: PIN_4
\SPI_MISO~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "input",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	oe => GND,
	padio => ww_SPI_MISO,
	dataout => \SPI_MISO~dataout\);

-- Location: LC30
\D_buff_pi[0]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_pi[0]_pterm0_bus\,
	pterm1 => \D_buff_pi[0]_pterm1_bus\,
	pterm2 => \D_buff_pi[0]_pterm2_bus\,
	pterm3 => \D_buff_pi[0]_pterm3_bus\,
	pterm4 => \D_buff_pi[0]_pterm4_bus\,
	pterm5 => \D_buff_pi[0]_pterm5_bus\,
	pxor => \D_buff_pi[0]_pxor_bus\,
	pclk => \D_buff_pi[0]_pclk_bus\,
	papre => \D_buff_pi[0]_papre_bus\,
	paclr => \D_buff_pi[0]_paclr_bus\,
	pena => \D_buff_pi[0]_pena_bus\,
	dataout => D_buff_pi(0));

-- Location: LC18
\D_buff_pi[1]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_pi[1]_pterm0_bus\,
	pterm1 => \D_buff_pi[1]_pterm1_bus\,
	pterm2 => \D_buff_pi[1]_pterm2_bus\,
	pterm3 => \D_buff_pi[1]_pterm3_bus\,
	pterm4 => \D_buff_pi[1]_pterm4_bus\,
	pterm5 => \D_buff_pi[1]_pterm5_bus\,
	pxor => \D_buff_pi[1]_pxor_bus\,
	pclk => \D_buff_pi[1]_pclk_bus\,
	papre => \D_buff_pi[1]_papre_bus\,
	paclr => \D_buff_pi[1]_paclr_bus\,
	pena => \D_buff_pi[1]_pena_bus\,
	dataout => D_buff_pi(1));

-- Location: SEXP52
\D~40sexp\ : max_sexp
PORT MAP (
	datain => \D~40sexp_datain_bus\,
	dataout => \D~40sexp_dataout\);

-- Location: LC53
\D[1]~47\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "xor",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[1]~47_pterm0_bus\,
	pterm1 => \D[1]~47_pterm1_bus\,
	pterm2 => \D[1]~47_pterm2_bus\,
	pterm3 => \D[1]~47_pterm3_bus\,
	pterm4 => \D[1]~47_pterm4_bus\,
	pterm5 => \D[1]~47_pterm5_bus\,
	pxor => \D[1]~47_pxor_bus\,
	pclk => \D[1]~47_pclk_bus\,
	papre => \D[1]~47_papre_bus\,
	paclr => \D[1]~47_paclr_bus\,
	pena => \D[1]~47_pena_bus\,
	dataout => \D[1]~47_dataout\);

-- Location: LC29
\D_buff_pi[2]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_pi[2]_pterm0_bus\,
	pterm1 => \D_buff_pi[2]_pterm1_bus\,
	pterm2 => \D_buff_pi[2]_pterm2_bus\,
	pterm3 => \D_buff_pi[2]_pterm3_bus\,
	pterm4 => \D_buff_pi[2]_pterm4_bus\,
	pterm5 => \D_buff_pi[2]_pterm5_bus\,
	pxor => \D_buff_pi[2]_pxor_bus\,
	pclk => \D_buff_pi[2]_pclk_bus\,
	papre => \D_buff_pi[2]_papre_bus\,
	paclr => \D_buff_pi[2]_paclr_bus\,
	pena => \D_buff_pi[2]_pena_bus\,
	dataout => D_buff_pi(2));

-- Location: LC20
\D[2]~53\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[2]~53_pterm0_bus\,
	pterm1 => \D[2]~53_pterm1_bus\,
	pterm2 => \D[2]~53_pterm2_bus\,
	pterm3 => \D[2]~53_pterm3_bus\,
	pterm4 => \D[2]~53_pterm4_bus\,
	pterm5 => \D[2]~53_pterm5_bus\,
	pxor => \D[2]~53_pxor_bus\,
	pclk => \D[2]~53_pclk_bus\,
	papre => \D[2]~53_papre_bus\,
	paclr => \D[2]~53_paclr_bus\,
	pena => \D[2]~53_pena_bus\,
	dataout => \D[2]~53_dataout\);

-- Location: LC22
\D_buff_pi[3]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_pi[3]_pterm0_bus\,
	pterm1 => \D_buff_pi[3]_pterm1_bus\,
	pterm2 => \D_buff_pi[3]_pterm2_bus\,
	pterm3 => \D_buff_pi[3]_pterm3_bus\,
	pterm4 => \D_buff_pi[3]_pterm4_bus\,
	pterm5 => \D_buff_pi[3]_pterm5_bus\,
	pxor => \D_buff_pi[3]_pxor_bus\,
	pclk => \D_buff_pi[3]_pclk_bus\,
	papre => \D_buff_pi[3]_papre_bus\,
	paclr => \D_buff_pi[3]_paclr_bus\,
	pena => \D_buff_pi[3]_pena_bus\,
	dataout => D_buff_pi(3));

-- Location: LC57
\D[3]~54\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "xor",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[3]~54_pterm0_bus\,
	pterm1 => \D[3]~54_pterm1_bus\,
	pterm2 => \D[3]~54_pterm2_bus\,
	pterm3 => \D[3]~54_pterm3_bus\,
	pterm4 => \D[3]~54_pterm4_bus\,
	pterm5 => \D[3]~54_pterm5_bus\,
	pxor => \D[3]~54_pxor_bus\,
	pclk => \D[3]~54_pclk_bus\,
	papre => \D[3]~54_papre_bus\,
	paclr => \D[3]~54_paclr_bus\,
	pena => \D[3]~54_pena_bus\,
	dataout => \D[3]~54_dataout\);

-- Location: LC28
\D_buff_pi[4]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_pi[4]_pterm0_bus\,
	pterm1 => \D_buff_pi[4]_pterm1_bus\,
	pterm2 => \D_buff_pi[4]_pterm2_bus\,
	pterm3 => \D_buff_pi[4]_pterm3_bus\,
	pterm4 => \D_buff_pi[4]_pterm4_bus\,
	pterm5 => \D_buff_pi[4]_pterm5_bus\,
	pxor => \D_buff_pi[4]_pxor_bus\,
	pclk => \D_buff_pi[4]_pclk_bus\,
	papre => \D_buff_pi[4]_papre_bus\,
	paclr => \D_buff_pi[4]_paclr_bus\,
	pena => \D_buff_pi[4]_pena_bus\,
	dataout => D_buff_pi(4));

-- Location: LC21
\D[4]~60\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[4]~60_pterm0_bus\,
	pterm1 => \D[4]~60_pterm1_bus\,
	pterm2 => \D[4]~60_pterm2_bus\,
	pterm3 => \D[4]~60_pterm3_bus\,
	pterm4 => \D[4]~60_pterm4_bus\,
	pterm5 => \D[4]~60_pterm5_bus\,
	pxor => \D[4]~60_pxor_bus\,
	pclk => \D[4]~60_pclk_bus\,
	papre => \D[4]~60_papre_bus\,
	paclr => \D[4]~60_paclr_bus\,
	pena => \D[4]~60_pena_bus\,
	dataout => \D[4]~60_dataout\);

-- Location: LC23
\D_buff_pi[5]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_pi[5]_pterm0_bus\,
	pterm1 => \D_buff_pi[5]_pterm1_bus\,
	pterm2 => \D_buff_pi[5]_pterm2_bus\,
	pterm3 => \D_buff_pi[5]_pterm3_bus\,
	pterm4 => \D_buff_pi[5]_pterm4_bus\,
	pterm5 => \D_buff_pi[5]_pterm5_bus\,
	pxor => \D_buff_pi[5]_pxor_bus\,
	pclk => \D_buff_pi[5]_pclk_bus\,
	papre => \D_buff_pi[5]_papre_bus\,
	paclr => \D_buff_pi[5]_paclr_bus\,
	pena => \D_buff_pi[5]_pena_bus\,
	dataout => D_buff_pi(5));

-- Location: LC64
\D[5]~62\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[5]~62_pterm0_bus\,
	pterm1 => \D[5]~62_pterm1_bus\,
	pterm2 => \D[5]~62_pterm2_bus\,
	pterm3 => \D[5]~62_pterm3_bus\,
	pterm4 => \D[5]~62_pterm4_bus\,
	pterm5 => \D[5]~62_pterm5_bus\,
	pxor => \D[5]~62_pxor_bus\,
	pclk => \D[5]~62_pclk_bus\,
	papre => \D[5]~62_papre_bus\,
	paclr => \D[5]~62_paclr_bus\,
	pena => \D[5]~62_pena_bus\,
	dataout => \D[5]~62_dataout\);

-- Location: LC24
\D_buff_pi[6]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_pi[6]_pterm0_bus\,
	pterm1 => \D_buff_pi[6]_pterm1_bus\,
	pterm2 => \D_buff_pi[6]_pterm2_bus\,
	pterm3 => \D_buff_pi[6]_pterm3_bus\,
	pterm4 => \D_buff_pi[6]_pterm4_bus\,
	pterm5 => \D_buff_pi[6]_pterm5_bus\,
	pxor => \D_buff_pi[6]_pxor_bus\,
	pclk => \D_buff_pi[6]_pclk_bus\,
	papre => \D_buff_pi[6]_papre_bus\,
	paclr => \D_buff_pi[6]_paclr_bus\,
	pena => \D_buff_pi[6]_pena_bus\,
	dataout => D_buff_pi(6));

-- Location: LC3
\D[6]~64\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[6]~64_pterm0_bus\,
	pterm1 => \D[6]~64_pterm1_bus\,
	pterm2 => \D[6]~64_pterm2_bus\,
	pterm3 => \D[6]~64_pterm3_bus\,
	pterm4 => \D[6]~64_pterm4_bus\,
	pterm5 => \D[6]~64_pterm5_bus\,
	pxor => \D[6]~64_pxor_bus\,
	pclk => \D[6]~64_pclk_bus\,
	papre => \D[6]~64_papre_bus\,
	paclr => \D[6]~64_paclr_bus\,
	pena => \D[6]~64_pena_bus\,
	dataout => \D[6]~64_dataout\);

-- Location: LC17
\D_buff_pi[7]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_pi[7]_pterm0_bus\,
	pterm1 => \D_buff_pi[7]_pterm1_bus\,
	pterm2 => \D_buff_pi[7]_pterm2_bus\,
	pterm3 => \D_buff_pi[7]_pterm3_bus\,
	pterm4 => \D_buff_pi[7]_pterm4_bus\,
	pterm5 => \D_buff_pi[7]_pterm5_bus\,
	pxor => \D_buff_pi[7]_pxor_bus\,
	pclk => \D_buff_pi[7]_pclk_bus\,
	papre => \D_buff_pi[7]_papre_bus\,
	paclr => \D_buff_pi[7]_paclr_bus\,
	pena => \D_buff_pi[7]_pena_bus\,
	dataout => D_buff_pi(7));

-- Location: LC41
\D[7]~66\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D[7]~66_pterm0_bus\,
	pterm1 => \D[7]~66_pterm1_bus\,
	pterm2 => \D[7]~66_pterm2_bus\,
	pterm3 => \D[7]~66_pterm3_bus\,
	pterm4 => \D[7]~66_pterm4_bus\,
	pterm5 => \D[7]~66_pterm5_bus\,
	pxor => \D[7]~66_pxor_bus\,
	pclk => \D[7]~66_pclk_bus\,
	papre => \D[7]~66_papre_bus\,
	paclr => \D[7]~66_paclr_bus\,
	pena => \D[7]~66_pena_bus\,
	dataout => \D[7]~66_dataout\);

-- Location: LC40
\~VCC~0\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "invert",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \~VCC~0_pterm0_bus\,
	pterm1 => \~VCC~0_pterm1_bus\,
	pterm2 => \~VCC~0_pterm2_bus\,
	pterm3 => \~VCC~0_pterm3_bus\,
	pterm4 => \~VCC~0_pterm4_bus\,
	pterm5 => \~VCC~0_pterm5_bus\,
	pxor => \~VCC~0_pxor_bus\,
	pclk => \~VCC~0_pclk_bus\,
	papre => \~VCC~0_papre_bus\,
	paclr => \~VCC~0_paclr_bus\,
	pena => \~VCC~0_pena_bus\,
	dataout => \~VCC~0~dataout\);

-- Location: LC46
\BUSDIR_n~4\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "invert",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \BUSDIR_n~4_pterm0_bus\,
	pterm1 => \BUSDIR_n~4_pterm1_bus\,
	pterm2 => \BUSDIR_n~4_pterm2_bus\,
	pterm3 => \BUSDIR_n~4_pterm3_bus\,
	pterm4 => \BUSDIR_n~4_pterm4_bus\,
	pterm5 => \BUSDIR_n~4_pterm5_bus\,
	pxor => \BUSDIR_n~4_pxor_bus\,
	pclk => \BUSDIR_n~4_pclk_bus\,
	papre => \BUSDIR_n~4_papre_bus\,
	paclr => \BUSDIR_n~4_paclr_bus\,
	pena => \BUSDIR_n~4_pena_bus\,
	dataout => \BUSDIR_n~4_dataout\);

-- Location: LC4
\SPI_en_s~16\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "invert",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \SPI_en_s~16_pterm0_bus\,
	pterm1 => \SPI_en_s~16_pterm1_bus\,
	pterm2 => \SPI_en_s~16_pterm2_bus\,
	pterm3 => \SPI_en_s~16_pterm3_bus\,
	pterm4 => \SPI_en_s~16_pterm4_bus\,
	pterm5 => \SPI_en_s~16_pterm5_bus\,
	pxor => \SPI_en_s~16_pxor_bus\,
	pclk => \SPI_en_s~16_pclk_bus\,
	papre => \SPI_en_s~16_papre_bus\,
	paclr => \SPI_en_s~16_paclr_bus\,
	pena => \SPI_en_s~16_pena_bus\,
	dataout => \SPI_en_s~16_dataout\);

-- Location: SEXP3
\D_buff_msx_r[7]~106\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[7]~106_datain_bus\,
	dataout => \D_buff_msx_r[7]~106_dataout\);

-- Location: LC5
\D_buff_msx[7]~62\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx[7]~62_pterm0_bus\,
	pterm1 => \D_buff_msx[7]~62_pterm1_bus\,
	pterm2 => \D_buff_msx[7]~62_pterm2_bus\,
	pterm3 => \D_buff_msx[7]~62_pterm3_bus\,
	pterm4 => \D_buff_msx[7]~62_pterm4_bus\,
	pterm5 => \D_buff_msx[7]~62_pterm5_bus\,
	pxor => \D_buff_msx[7]~62_pxor_bus\,
	pclk => \D_buff_msx[7]~62_pclk_bus\,
	papre => \D_buff_msx[7]~62_papre_bus\,
	paclr => \D_buff_msx[7]~62_paclr_bus\,
	pena => \D_buff_msx[7]~62_pena_bus\,
	dataout => \D_buff_msx[7]~62_dataout\);

-- Location: SEXP4
\D_buff_msx_r[7]~107\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[7]~107_datain_bus\,
	dataout => \D_buff_msx_r[7]~107_dataout\);

-- Location: SEXP5
\D_buff_msx_r[7]~108\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[7]~108_datain_bus\,
	dataout => \D_buff_msx_r[7]~108_dataout\);

-- Location: SEXP8
\D_buff_pi[0]~86\ : max_sexp
PORT MAP (
	datain => \D_buff_pi[0]~86_datain_bus\,
	dataout => \D_buff_pi[0]~86_dataout\);

-- Location: SEXP61
\D_buff_msx_r[6]~94\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[6]~94_datain_bus\,
	dataout => \D_buff_msx_r[6]~94_dataout\);

-- Location: LC56
\D_buff_msx[6]~58\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx[6]~58_pterm0_bus\,
	pterm1 => \D_buff_msx[6]~58_pterm1_bus\,
	pterm2 => \D_buff_msx[6]~58_pterm2_bus\,
	pterm3 => \D_buff_msx[6]~58_pterm3_bus\,
	pterm4 => \D_buff_msx[6]~58_pterm4_bus\,
	pterm5 => \D_buff_msx[6]~58_pterm5_bus\,
	pxor => \D_buff_msx[6]~58_pxor_bus\,
	pclk => \D_buff_msx[6]~58_pclk_bus\,
	papre => \D_buff_msx[6]~58_papre_bus\,
	paclr => \D_buff_msx[6]~58_paclr_bus\,
	pena => \D_buff_msx[6]~58_pena_bus\,
	dataout => \D_buff_msx[6]~58_dataout\);

-- Location: SEXP64
\D_buff_msx_r[6]~95\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[6]~95_datain_bus\,
	dataout => \D_buff_msx_r[6]~95_dataout\);

-- Location: SEXP49
\D_buff_msx_r[6]~96\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[6]~96_datain_bus\,
	dataout => \D_buff_msx_r[6]~96_dataout\);

-- Location: SEXP59
\D_buff_pi[0]~85\ : max_sexp
PORT MAP (
	datain => \D_buff_pi[0]~85_datain_bus\,
	dataout => \D_buff_pi[0]~85_dataout\);

-- Location: SEXP56
\D_buff_msx_r[5]~82\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[5]~82_datain_bus\,
	dataout => \D_buff_msx_r[5]~82_dataout\);

-- Location: LC51
\D_buff_msx[5]~54\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx[5]~54_pterm0_bus\,
	pterm1 => \D_buff_msx[5]~54_pterm1_bus\,
	pterm2 => \D_buff_msx[5]~54_pterm2_bus\,
	pterm3 => \D_buff_msx[5]~54_pterm3_bus\,
	pterm4 => \D_buff_msx[5]~54_pterm4_bus\,
	pterm5 => \D_buff_msx[5]~54_pterm5_bus\,
	pxor => \D_buff_msx[5]~54_pxor_bus\,
	pclk => \D_buff_msx[5]~54_pclk_bus\,
	papre => \D_buff_msx[5]~54_papre_bus\,
	paclr => \D_buff_msx[5]~54_paclr_bus\,
	pena => \D_buff_msx[5]~54_pena_bus\,
	dataout => \D_buff_msx[5]~54_dataout\);

-- Location: SEXP57
\D_buff_msx_r[5]~83\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[5]~83_datain_bus\,
	dataout => \D_buff_msx_r[5]~83_dataout\);

-- Location: SEXP58
\D_buff_msx_r[5]~84\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[5]~84_datain_bus\,
	dataout => \D_buff_msx_r[5]~84_dataout\);

-- Location: SEXP35
\D_buff_msx_r[4]~70\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[4]~70_datain_bus\,
	dataout => \D_buff_msx_r[4]~70_dataout\);

-- Location: LC37
\D_buff_msx[4]~50\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx[4]~50_pterm0_bus\,
	pterm1 => \D_buff_msx[4]~50_pterm1_bus\,
	pterm2 => \D_buff_msx[4]~50_pterm2_bus\,
	pterm3 => \D_buff_msx[4]~50_pterm3_bus\,
	pterm4 => \D_buff_msx[4]~50_pterm4_bus\,
	pterm5 => \D_buff_msx[4]~50_pterm5_bus\,
	pxor => \D_buff_msx[4]~50_pxor_bus\,
	pclk => \D_buff_msx[4]~50_pclk_bus\,
	papre => \D_buff_msx[4]~50_papre_bus\,
	paclr => \D_buff_msx[4]~50_paclr_bus\,
	pena => \D_buff_msx[4]~50_pena_bus\,
	dataout => \D_buff_msx[4]~50_dataout\);

-- Location: SEXP37
\D_buff_msx_r[4]~71\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[4]~71_datain_bus\,
	dataout => \D_buff_msx_r[4]~71_dataout\);

-- Location: SEXP36
\D_buff_msx_r[4]~72\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[4]~72_datain_bus\,
	dataout => \D_buff_msx_r[4]~72_dataout\);

-- Location: SEXP44
\D_buff_pi[0]~84\ : max_sexp
PORT MAP (
	datain => \D_buff_pi[0]~84_datain_bus\,
	dataout => \D_buff_pi[0]~84_dataout\);

-- Location: SEXP51
\D_buff_msx_r[3]~58\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[3]~58_datain_bus\,
	dataout => \D_buff_msx_r[3]~58_dataout\);

-- Location: LC54
\D_buff_msx[3]~46\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx[3]~46_pterm0_bus\,
	pterm1 => \D_buff_msx[3]~46_pterm1_bus\,
	pterm2 => \D_buff_msx[3]~46_pterm2_bus\,
	pterm3 => \D_buff_msx[3]~46_pterm3_bus\,
	pterm4 => \D_buff_msx[3]~46_pterm4_bus\,
	pterm5 => \D_buff_msx[3]~46_pterm5_bus\,
	pxor => \D_buff_msx[3]~46_pxor_bus\,
	pclk => \D_buff_msx[3]~46_pclk_bus\,
	papre => \D_buff_msx[3]~46_papre_bus\,
	paclr => \D_buff_msx[3]~46_paclr_bus\,
	pena => \D_buff_msx[3]~46_pena_bus\,
	dataout => \D_buff_msx[3]~46_dataout\);

-- Location: SEXP53
\D_buff_msx_r[3]~59\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[3]~59_datain_bus\,
	dataout => \D_buff_msx_r[3]~59_dataout\);

-- Location: SEXP54
\D_buff_msx_r[3]~60\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[3]~60_datain_bus\,
	dataout => \D_buff_msx_r[3]~60_dataout\);

-- Location: SEXP48
\D_buff_msx_r[2]~46\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[2]~46_datain_bus\,
	dataout => \D_buff_msx_r[2]~46_dataout\);

-- Location: LC36
\D_buff_msx[2]~42\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx[2]~42_pterm0_bus\,
	pterm1 => \D_buff_msx[2]~42_pterm1_bus\,
	pterm2 => \D_buff_msx[2]~42_pterm2_bus\,
	pterm3 => \D_buff_msx[2]~42_pterm3_bus\,
	pterm4 => \D_buff_msx[2]~42_pterm4_bus\,
	pterm5 => \D_buff_msx[2]~42_pterm5_bus\,
	pxor => \D_buff_msx[2]~42_pxor_bus\,
	pclk => \D_buff_msx[2]~42_pclk_bus\,
	papre => \D_buff_msx[2]~42_papre_bus\,
	paclr => \D_buff_msx[2]~42_paclr_bus\,
	pena => \D_buff_msx[2]~42_pena_bus\,
	dataout => \D_buff_msx[2]~42_dataout\);

-- Location: SEXP43
\D_buff_msx_r[2]~47\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[2]~47_datain_bus\,
	dataout => \D_buff_msx_r[2]~47_dataout\);

-- Location: SEXP33
\D_buff_msx_r[2]~48\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[2]~48_datain_bus\,
	dataout => \D_buff_msx_r[2]~48_dataout\);

-- Location: SEXP40
\D_buff_msx_r[1]~34\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[1]~34_datain_bus\,
	dataout => \D_buff_msx_r[1]~34_dataout\);

-- Location: LC61
\D_buff_msx[1]~38\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx[1]~38_pterm0_bus\,
	pterm1 => \D_buff_msx[1]~38_pterm1_bus\,
	pterm2 => \D_buff_msx[1]~38_pterm2_bus\,
	pterm3 => \D_buff_msx[1]~38_pterm3_bus\,
	pterm4 => \D_buff_msx[1]~38_pterm4_bus\,
	pterm5 => \D_buff_msx[1]~38_pterm5_bus\,
	pxor => \D_buff_msx[1]~38_pxor_bus\,
	pclk => \D_buff_msx[1]~38_pclk_bus\,
	papre => \D_buff_msx[1]~38_papre_bus\,
	paclr => \D_buff_msx[1]~38_paclr_bus\,
	pena => \D_buff_msx[1]~38_pena_bus\,
	dataout => \D_buff_msx[1]~38_dataout\);

-- Location: SEXP41
\D_buff_msx_r[1]~35\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[1]~35_datain_bus\,
	dataout => \D_buff_msx_r[1]~35_dataout\);

-- Location: SEXP46
\D_buff_msx_r[1]~36\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[1]~36_datain_bus\,
	dataout => \D_buff_msx_r[1]~36_dataout\);

-- Location: LC58
\D_buff_msx[0]~34\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "comb",
	pexp_mode => "off")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx[0]~34_pterm0_bus\,
	pterm1 => \D_buff_msx[0]~34_pterm1_bus\,
	pterm2 => \D_buff_msx[0]~34_pterm2_bus\,
	pterm3 => \D_buff_msx[0]~34_pterm3_bus\,
	pterm4 => \D_buff_msx[0]~34_pterm4_bus\,
	pterm5 => \D_buff_msx[0]~34_pterm5_bus\,
	pxor => \D_buff_msx[0]~34_pxor_bus\,
	pclk => \D_buff_msx[0]~34_pclk_bus\,
	papre => \D_buff_msx[0]~34_papre_bus\,
	paclr => \D_buff_msx[0]~34_paclr_bus\,
	pena => \D_buff_msx[0]~34_pena_bus\,
	dataout => \D_buff_msx[0]~34_dataout\);

-- Location: LC1
\spi_state.prepare\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "tff")
-- pragma translate_on
PORT MAP (
	pterm0 => \spi_state.prepare_pterm0_bus\,
	pterm1 => \spi_state.prepare_pterm1_bus\,
	pterm2 => \spi_state.prepare_pterm2_bus\,
	pterm3 => \spi_state.prepare_pterm3_bus\,
	pterm4 => \spi_state.prepare_pterm4_bus\,
	pterm5 => \spi_state.prepare_pterm5_bus\,
	pxor => \spi_state.prepare_pxor_bus\,
	pclk => \spi_state.prepare_pclk_bus\,
	papre => \spi_state.prepare_papre_bus\,
	paclr => \spi_state.prepare_paclr_bus\,
	pena => \spi_state.prepare_pena_bus\,
	dataout => \spi_state.prepare~dataout\);

-- Location: LC42
\D_buff_msx_r[0]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "tff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx_r[0]_pterm0_bus\,
	pterm1 => \D_buff_msx_r[0]_pterm1_bus\,
	pterm2 => \D_buff_msx_r[0]_pterm2_bus\,
	pterm3 => \D_buff_msx_r[0]_pterm3_bus\,
	pterm4 => \D_buff_msx_r[0]_pterm4_bus\,
	pterm5 => \D_buff_msx_r[0]_pterm5_bus\,
	pxor => \D_buff_msx_r[0]_pxor_bus\,
	pclk => \D_buff_msx_r[0]_pclk_bus\,
	papre => \D_buff_msx_r[0]_papre_bus\,
	paclr => \D_buff_msx_r[0]_paclr_bus\,
	pena => \D_buff_msx_r[0]_pena_bus\,
	dataout => D_buff_msx_r(0));

-- Location: SEXP39
\D_buff_msx_r[1]~33\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[1]~33_datain_bus\,
	dataout => \D_buff_msx_r[1]~33_dataout\);

-- Location: LC45
\D_buff_msx_r[1]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "xor",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx_r[1]_pterm0_bus\,
	pterm1 => \D_buff_msx_r[1]_pterm1_bus\,
	pterm2 => \D_buff_msx_r[1]_pterm2_bus\,
	pterm3 => \D_buff_msx_r[1]_pterm3_bus\,
	pterm4 => \D_buff_msx_r[1]_pterm4_bus\,
	pterm5 => \D_buff_msx_r[1]_pterm5_bus\,
	pxor => \D_buff_msx_r[1]_pxor_bus\,
	pclk => \D_buff_msx_r[1]_pclk_bus\,
	papre => \D_buff_msx_r[1]_papre_bus\,
	paclr => \D_buff_msx_r[1]_paclr_bus\,
	pena => \D_buff_msx_r[1]_pena_bus\,
	dataout => D_buff_msx_r(1));

-- Location: LC38
\D_buff_msx_r[2]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "xor",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx_r[2]_pterm0_bus\,
	pterm1 => \D_buff_msx_r[2]_pterm1_bus\,
	pterm2 => \D_buff_msx_r[2]_pterm2_bus\,
	pterm3 => \D_buff_msx_r[2]_pterm3_bus\,
	pterm4 => \D_buff_msx_r[2]_pterm4_bus\,
	pterm5 => \D_buff_msx_r[2]_pterm5_bus\,
	pxor => \D_buff_msx_r[2]_pxor_bus\,
	pclk => \D_buff_msx_r[2]_pclk_bus\,
	papre => \D_buff_msx_r[2]_papre_bus\,
	paclr => \D_buff_msx_r[2]_paclr_bus\,
	pena => \D_buff_msx_r[2]_pena_bus\,
	dataout => D_buff_msx_r(2));

-- Location: SEXP62
\D_buff_msx_r[1]~118\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[1]~118_datain_bus\,
	dataout => \D_buff_msx_r[1]~118_dataout\);

-- Location: LC60
\D_buff_msx_r[3]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "xor",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx_r[3]_pterm0_bus\,
	pterm1 => \D_buff_msx_r[3]_pterm1_bus\,
	pterm2 => \D_buff_msx_r[3]_pterm2_bus\,
	pterm3 => \D_buff_msx_r[3]_pterm3_bus\,
	pterm4 => \D_buff_msx_r[3]_pterm4_bus\,
	pterm5 => \D_buff_msx_r[3]_pterm5_bus\,
	pxor => \D_buff_msx_r[3]_pxor_bus\,
	pclk => \D_buff_msx_r[3]_pclk_bus\,
	papre => \D_buff_msx_r[3]_papre_bus\,
	paclr => \D_buff_msx_r[3]_paclr_bus\,
	pena => \D_buff_msx_r[3]_pena_bus\,
	dataout => D_buff_msx_r(3));

-- Location: LC34
\D_buff_msx_r[4]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "xor",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx_r[4]_pterm0_bus\,
	pterm1 => \D_buff_msx_r[4]_pterm1_bus\,
	pterm2 => \D_buff_msx_r[4]_pterm2_bus\,
	pterm3 => \D_buff_msx_r[4]_pterm3_bus\,
	pterm4 => \D_buff_msx_r[4]_pterm4_bus\,
	pterm5 => \D_buff_msx_r[4]_pterm5_bus\,
	pxor => \D_buff_msx_r[4]_pxor_bus\,
	pclk => \D_buff_msx_r[4]_pclk_bus\,
	papre => \D_buff_msx_r[4]_papre_bus\,
	paclr => \D_buff_msx_r[4]_paclr_bus\,
	pena => \D_buff_msx_r[4]_pena_bus\,
	dataout => D_buff_msx_r(4));

-- Location: LC55
\D_buff_msx_r[5]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "xor",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx_r[5]_pterm0_bus\,
	pterm1 => \D_buff_msx_r[5]_pterm1_bus\,
	pterm2 => \D_buff_msx_r[5]_pterm2_bus\,
	pterm3 => \D_buff_msx_r[5]_pterm3_bus\,
	pterm4 => \D_buff_msx_r[5]_pterm4_bus\,
	pterm5 => \D_buff_msx_r[5]_pterm5_bus\,
	pxor => \D_buff_msx_r[5]_pxor_bus\,
	pclk => \D_buff_msx_r[5]_pclk_bus\,
	papre => \D_buff_msx_r[5]_papre_bus\,
	paclr => \D_buff_msx_r[5]_paclr_bus\,
	pena => \D_buff_msx_r[5]_pena_bus\,
	dataout => D_buff_msx_r(5));

-- Location: LC50
\D_buff_msx_r[6]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "xor",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx_r[6]_pterm0_bus\,
	pterm1 => \D_buff_msx_r[6]_pterm1_bus\,
	pterm2 => \D_buff_msx_r[6]_pterm2_bus\,
	pterm3 => \D_buff_msx_r[6]_pterm3_bus\,
	pterm4 => \D_buff_msx_r[6]_pterm4_bus\,
	pterm5 => \D_buff_msx_r[6]_pterm5_bus\,
	pxor => \D_buff_msx_r[6]_pxor_bus\,
	pclk => \D_buff_msx_r[6]_pclk_bus\,
	papre => \D_buff_msx_r[6]_papre_bus\,
	paclr => \D_buff_msx_r[6]_paclr_bus\,
	pena => \D_buff_msx_r[6]_pena_bus\,
	dataout => D_buff_msx_r(6));

-- Location: SEXP9
\D_buff_msx_r[1]~119\ : max_sexp
PORT MAP (
	datain => \D_buff_msx_r[1]~119_datain_bus\,
	dataout => \D_buff_msx_r[1]~119_dataout\);

-- Location: LC6
\D_buff_msx_r[7]\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "xor",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "dff")
-- pragma translate_on
PORT MAP (
	pterm0 => \D_buff_msx_r[7]_pterm0_bus\,
	pterm1 => \D_buff_msx_r[7]_pterm1_bus\,
	pterm2 => \D_buff_msx_r[7]_pterm2_bus\,
	pterm3 => \D_buff_msx_r[7]_pterm3_bus\,
	pterm4 => \D_buff_msx_r[7]_pterm4_bus\,
	pterm5 => \D_buff_msx_r[7]_pterm5_bus\,
	pxor => \D_buff_msx_r[7]_pxor_bus\,
	pclk => \D_buff_msx_r[7]_pclk_bus\,
	papre => \D_buff_msx_r[7]_papre_bus\,
	paclr => \D_buff_msx_r[7]_paclr_bus\,
	pena => \D_buff_msx_r[7]_pena_bus\,
	dataout => D_buff_msx_r(7));

-- Location: LC11
\SPI_MOSI~reg0\ : max_mcell
-- pragma translate_off
GENERIC MAP (
	operation_mode => "normal",
	output_mode => "reg",
	pexp_mode => "off",
	power_up => "low",
	register_mode => "tff")
-- pragma translate_on
PORT MAP (
	pterm0 => \SPI_MOSI~reg0_pterm0_bus\,
	pterm1 => \SPI_MOSI~reg0_pterm1_bus\,
	pterm2 => \SPI_MOSI~reg0_pterm2_bus\,
	pterm3 => \SPI_MOSI~reg0_pterm3_bus\,
	pterm4 => \SPI_MOSI~reg0_pterm4_bus\,
	pterm5 => \SPI_MOSI~reg0_pterm5_bus\,
	pxor => \SPI_MOSI~reg0_pxor_bus\,
	pclk => \SPI_MOSI~reg0_pclk_bus\,
	papre => \SPI_MOSI~reg0_papre_bus\,
	paclr => \SPI_MOSI~reg0_paclr_bus\,
	pena => \SPI_MOSI~reg0_pena_bus\,
	dataout => \SPI_MOSI~reg0_dataout\);

-- Location: PIN_28
\WAIT_n~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "true",
	operation_mode => "output",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \~VCC~0~dataout\,
	oe => VCC,
	padio => ww_WAIT_n);

-- Location: PIN_31
\BUSDIR_n~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "output",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \BUSDIR_n~4_dataout\,
	oe => VCC,
	padio => ww_BUSDIR_n);

-- Location: PIN_9
\SPI_CS~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "output",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \SPI_en_s~16_dataout\,
	oe => VCC,
	padio => ww_SPI_CS);

-- Location: PIN_6
\SPI_MOSI~I\ : max_io
-- pragma translate_off
GENERIC MAP (
	bus_hold => "false",
	open_drain_output => "false",
	operation_mode => "output",
	weak_pull_up => "false")
-- pragma translate_on
PORT MAP (
	datain => \SPI_MOSI~reg0_dataout\,
	oe => VCC,
	padio => ww_SPI_MOSI);
END structure;


