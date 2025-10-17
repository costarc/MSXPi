-- ==============================================================================
-- MSXPi Interface - Version 1.3
-- ==============================================================================
-- MIT License
-- Copyright (c) 2015 - 2025 Ronivon Costa
-- Permission is hereby granted, free of charge, to use, copy, modify, merge,
-- publish, distribute, sublicense, and/or sell copies of the Software.
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
-- ==============================================================================

-- ==============================================================================
-- Project History
-- ------------------------------------------------------------------------------
-- Ronivon Candido Costa - 22/10/2016
-- MSX_Interface using new proto board
-- CPLD: V0.5 | MSX: bootv5.bin | Pi: msx.c (v1.5)
--
-- Version 0.5   - Initial prototype with Pi Zero
-- Version 0.6   - Added SPI_RDY signal
-- Version 0.7   - Added BUSDIR signal
-- Version 0.7R4 - Added msxpi_package, port range 0x56–0x5D
-- Version 1.0   - Firmware version "1001" for PCB v1.0.1; Added /WAIT signal (LED driven by SPI_CS)
-- Version 1.1   - Firmware version "1010" for PCB v1.0.1
-- Version 1.2   - Firmware version "1011" for PCB V1.1, 1.2"
-- Version 1.2.1b- Firmware version "1100", logic optimisation, openMSX support
-- Version 1.3   - Firmware version "1101", more logic optimisation & PLCC AT28C256
-- ==============================================================================

-- ==============================================================================
-- MSXPi Versions
-- ------------------------------------------------------------------------------
-- 0001–1011: Various prototypes and releases using EPM3064 and EPM7128
-- ==============================================================================

-- ==============================================================================
-- Libraries
-- ==============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.msxpi_package.all;

-- ==============================================================================
-- Entity Declaration
-- ==============================================================================
entity MSXPi is
    port (
        D           : inout std_logic_vector(7 downto 0);
        A           : in    std_logic_vector(7 downto 0);
        IORQ_n      : in    std_logic;
        RD_n        : in    std_logic;
        WR_n        : in    std_logic;
        BUSDIR_n    : out   std_logic;
        WAIT_n      : out   std_logic;
        SPI_CS      : out   std_logic;
        SPI_SCLK    : in    std_logic;
        SPI_MOSI    : out   std_logic;
        SPI_MISO    : in    std_logic;
        SPI_RDY     : in    std_logic
    );
end MSXPi;

-- ==============================================================================
-- Architecture
-- ==============================================================================
architecture rtl of MSXPi is

    -- FSM definition
    type fsm_type is (idle, prepare, transferring);
    signal spi_state        : fsm_type := idle;

    -- Control signals
    signal readoper         : std_logic;
    signal writeoper        : std_logic;
    signal spi_en           : std_logic;
    signal RESET            : std_logic;

    -- Data buffers
    signal D_buff_msx       : std_logic_vector(7 downto 0);
    signal D_buff_pi        : std_logic_vector(7 downto 0);
    signal D_buff_msx_r     : std_logic_vector(7 downto 0);
    signal D_out            : std_logic_vector(7 downto 0);

    -- SPI control
    signal SPI_en_s         : std_logic := '0';
    signal SPI_RDY_s        : std_logic;
    signal bitcount         : unsigned(2 downto 0) := (others => '0');

    -- Address decode helper
    signal is_ctrl_or_data  : std_logic;

begin

    -- ==========================================================================
    -- Port Decoding and Control
    -- ==========================================================================
    WAIT_n       <= 'Z';  -- Maintain in Tri-State - not driven by MSXPi
    is_ctrl_or_data <= '1' when A = CTRLPORT1 or A = DATAPORT1 else '0';

    BUSDIR_n     <= '0' when (readoper = '1' and is_ctrl_or_data = '1') else '1';
    readoper     <= not (IORQ_n or RD_n);
    writeoper    <= not (IORQ_n or WR_n);
    spi_en       <= '1' when (writeoper = '1' and is_ctrl_or_data = '1') else '0';

    -- SPI status logic
    SPI_RDY_s    <= SPI_en_s or (not SPI_RDY);

    -- Reset condition
    RESET        <= '1' when (writeoper = '1' and A = CTRLPORT1 and D = x"FF") else '0';

    -- MSX write buffer
    D_buff_msx   <= D when (writeoper = '1' and is_ctrl_or_data = '1');

    -- ==========================================================================
    -- D Bus Output Logic
    -- ==========================================================================
    process(A, SPI_RDY_s, D_buff_pi)
    begin
        if A = CTRLPORT1 then
            D_out <= "0000000" & SPI_RDY_s;
        elsif A = DATAPORT1 then
            D_out <= D_buff_pi;
        elsif A = CTRLPORT2 then
            D_out <= "0000" & MSXPIVer;
        else
            D_out <= (others => 'Z');
        end if;
    end process;

    D <= D_out when readoper = '1' else (others => 'Z');

    -- ==========================================================================
    -- SPI Serialization & Transfer Process
    -- ==========================================================================
    spi: process(RESET, SPI_SCLK, readoper, writeoper, SPI_en_s, spi_en)
    begin
        if RESET = '1' then
            SPI_en_s     <= '0';
            D_buff_pi    <= "00000000";
            spi_state    <= idle;

        elsif (SPI_en_s = '0' and spi_en = '1') then
            SPI_en_s     <= '1';
            bitcount     <= "000";
            spi_state    <= prepare;

        elsif rising_edge(SPI_SCLK) then
            case spi_state is
                when idle =>
                    SPI_en_s <= '0';

                when prepare =>
                    D_buff_msx_r <= D_buff_msx;
                    spi_state    <= transferring;

                when transferring =>
                    D_buff_pi      <= D_buff_pi(6 downto 0) & SPI_MISO;
                    SPI_MOSI       <= D_buff_msx_r(7);
                    D_buff_msx_r(7 downto 1) <= D_buff_msx_r(6 downto 0);
                    bitcount       <= bitcount + 1;

                    if bitcount = "111" then
                        spi_state <= idle;
                    end if;
            end case;
        end if;

        SPI_CS <= not SPI_en_s;
    end process;

end rtl;