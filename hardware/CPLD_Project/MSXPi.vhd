-- MSXPi Interface - Fully Quartus-Compatible
-- Version 1.1 Optimized
-- Author: Ronivon Costa
-- License: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.msxpi_package.all;

entity MSXPi is
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
end MSXPi;

architecture rtl of MSXPi is

    -- SPI FSM
    type fsm_type is (idle, transferring);
    signal spi_state    : fsm_type := idle;

    -- Control signals
    signal readoper     : std_logic;
    signal writeoper    : std_logic;
    signal spi_en       : std_logic;
    signal reset_req    : std_logic;

    -- Buffers
    signal D_buff_msx   : std_logic_vector(7 downto 0);
    signal D_buff_pi    : std_logic_vector(7 downto 0);
    signal D_shift      : std_logic_vector(7 downto 0);

    -- SPI counter
    signal bit_count    : unsigned(2 downto 0) := "000";

    -- SPI busy flag
    signal SPI_busy     : std_logic := '0';

    -- SPI_RDY for MSX
    signal SPI_RDY_s    : std_logic;

    -- Port mask functions
    function is_ctrl_port(addr : std_logic_vector(7 downto 0)) return boolean is
    begin
        return (addr(7 downto 4) = "0101") and (unsigned(addr(3 downto 0)) <= 9);
    end function;

    function is_data_port(addr : std_logic_vector(7 downto 0)) return boolean is
    begin
        return (addr(7 downto 4) = "0101") and 
               (unsigned(addr(3 downto 0)) >= 10) and 
               (unsigned(addr(3 downto 0)) <= 13);
    end function;

begin

    -- Read/Write detection
    readoper  <= not (IORQ_n or RD_n);
    writeoper <= not (IORQ_n or WR_n);

    -- SPI enable (using boolean functions)
    spi_en <= '1' when writeoper = '1' and (is_ctrl_port(A) or is_data_port(A)) else '0';

    -- BUS direction
    BUSDIR_n <= '0' when readoper = '1' and (is_ctrl_port(A) or is_data_port(A)) else '1';

    -- SPI_RDY output
    SPI_RDY_s <= SPI_busy or not SPI_RDY;

    -- Data output to MSX
    D <= "0000000" & SPI_RDY_s          when readoper = '1' and A = CTRLPORT1 else
         D_buff_pi                      when readoper = '1' and is_data_port(A) else
         "0000" & MSXPIVer              when readoper = '1' and A = CTRLPORT2 else
         "ZZZZZZZZ";

    -- Latch written MSX data
    process(writeoper, D, A)
    begin
        if writeoper = '1' and (is_ctrl_port(A) or is_data_port(A)) then
            D_buff_msx <= D;
        end if;
    end process;

    -- Reset request (bitwise comparison to avoid Quartus errors)
    reset_req <= '1' when writeoper = '1' and A = CTRLPORT1 and D = "11111111" else '0';

    -- SPI FSM
    process(SPI_SCLK, reset_req)
    begin
        if reset_req = '1' then
            SPI_busy   <= '0';
            D_buff_pi  <= (others => '0');
            spi_state  <= idle;
            bit_count  <= (others => '0');
            D_shift    <= (others => '0');
            SPI_MOSI   <= '0';
        elsif rising_edge(SPI_SCLK) then
            case spi_state is
                when idle =>
                    if spi_en = '1' then
                        SPI_busy  <= '1';
                        D_shift   <= D_buff_msx;
                        bit_count <= (others => '0');
                        spi_state <= transferring;
                    else
                        SPI_busy <= '0';
                    end if;

                when transferring =>
                    SPI_MOSI        <= D_shift(7);
                    D_shift(6 downto 0) <= D_shift(7 downto 1);
                    D_buff_pi       <= D_buff_pi(6 downto 0) & SPI_MISO;

                    bit_count       <= bit_count + 1;
                    if bit_count = "111" then
                        spi_state <= idle;
                        SPI_busy  <= '0';
                    end if;
            end case;
        end if;
    end process;

    -- SPI CS output
    SPI_CS <= not SPI_busy;

    -- WAIT_n tri-state for MSX bus
    WAIT_n <= 'Z';

end rtl;
