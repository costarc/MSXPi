-- MSXPi Testbench for GTKWave
-- Author: Ronivon Costa
-- License: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.msxpi_package.all;

entity tb_MSXPi is
-- Testbench has no ports
end tb_MSXPi;

architecture sim of tb_MSXPi is

    -- Component under test
    component MSXPi is
        port(
            D        : inout std_logic_vector(7 downto 0);
            A        : in    std_logic_vector(7 downto 0);
            IORQ_n   : in    std_logic;
            RD_n     : in    std_logic;
            WR_n     : in    std_logic;
            BUSDIR_n : out   std_logic;
            WAIT_n   : out   std_logic;
            SPI_CS   : out   std_logic;
            SPI_SCLK : in    std_logic;
            SPI_MOSI : out   std_logic;
            SPI_MISO : in    std_logic;
            SPI_RDY  : in    std_logic
        );
    end component;

    -- Signals
    signal D        : std_logic_vector(7 downto 0) := (others => '0');
    signal A        : std_logic_vector(7 downto 0) := (others => '0');
    signal IORQ_n   : std_logic := '1';
    signal RD_n     : std_logic := '1';
    signal WR_n     : std_logic := '1';
    signal BUSDIR_n : std_logic;
    signal WAIT_n   : std_logic;
    signal SPI_CS   : std_logic;
    signal SPI_SCLK : std_logic := '0';
    signal SPI_MOSI : std_logic;
    signal SPI_MISO : std_logic := '0';
    signal SPI_RDY  : std_logic := '1';

    -- Clock period
    constant CLK_PERIOD : time := 100 ns;

begin

    -- Instantiate DUT
    DUT: MSXPi
        port map(
            D        => D,
            A        => A,
            IORQ_n   => IORQ_n,
            RD_n     => RD_n,
            WR_n     => WR_n,
            BUSDIR_n => BUSDIR_n,
            WAIT_n   => WAIT_n,
            SPI_CS   => SPI_CS,
            SPI_SCLK => SPI_SCLK,
            SPI_MOSI => SPI_MOSI,
            SPI_MISO => SPI_MISO,
            SPI_RDY  => SPI_RDY
        );

    -- SPI Clock Generation
    clk_proc: process
    begin
        while true loop
            SPI_SCLK <= '0';
            wait for CLK_PERIOD / 2;
            SPI_SCLK <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
    end process;

    -- Stimulus process
    stim_proc: process
    begin
        -- Initial delay
        wait for 200 ns;

        -- Write 0xFF to CTRLPORT1 (should trigger reset)
        A      <= CTRLPORT1;
        D      <= "11111111";
        IORQ_n <= '0';
        WR_n   <= '0';
        wait for CLK_PERIOD;
        IORQ_n <= '1';
        WR_n   <= '1';
        wait for CLK_PERIOD;

        -- Write some data to DATAPORT1
        A      <= DATAPORT1;
        D      <= "10101010";
        IORQ_n <= '0';
        WR_n   <= '0';
        wait for CLK_PERIOD;
        IORQ_n <= '1';
        WR_n   <= '1';
        wait for CLK_PERIOD;

        -- Read CTRLPORT1
        A    <= CTRLPORT1;
        IORQ_n <= '0';
        RD_n   <= '0';
        wait for CLK_PERIOD;
        IORQ_n <= '1';
        RD_n   <= '1';
        wait for CLK_PERIOD;

        -- Simulate SPI MISO data
        SPI_MISO <= '1';
        wait for CLK_PERIOD;
        SPI_MISO <= '0';
        wait for CLK_PERIOD;

        -- End simulation
        wait for 1 us;
        assert false report "End of simulation" severity note;
        wait;
    end process;

end sim;
