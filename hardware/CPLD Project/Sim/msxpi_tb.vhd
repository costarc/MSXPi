library ieee ;
use ieee.std_logic_1164.all; 
use ieee.numeric_std.all;

entity msxpi_tb is
end msxpi_tb;

architecture tb of msxpi_tb is
	component msxpi is
		port (
			d			: inout std_logic_vector(7 downto 0);
			a			: in std_logic_vector(7 downto 0);
			iorq_n		: in std_logic;
			rd_n		: in std_logic;
			wr_n		: in std_logic;
			wait_n		: out std_logic;
			busdir_n	: out std_logic;
			spi_cs		: out std_logic;
			spi_sclk	: in std_logic;
			spi_mosi	: out std_logic;
			spi_miso	: in std_logic;
			spi_rdy  	: in std_logic);
	end component;

	constant bus_size : integer := 16; -- Address + Data sizes
	constant bus_control_size : integer := 3;
	
	type state_type is (idle, prepare_spi, send_bus_data, receive_bus_data);
	signal spi_state, next_state	: state_type := idle;	

	signal a_s		 	: std_logic_vector(7 downto 0);
	signal d_s	 	    : std_logic_vector(7 downto 0);
	signal iorq_n_s		: std_logic;
	signal rd_n_s		: std_logic;
	signal wr_n_s		: std_logic;
	signal wait_n_s		: std_logic;
	signal busdir_n_s	: std_logic;
	signal spi_cs_s 	: std_logic;
	signal spi_clk_s	: std_logic;
	signal spi_mosi_s	: std_logic;
	signal spi_miso_s	: std_logic;
	signal rpi_rdy_s	: std_logic;

begin

	msxpi_instance: msxpi
		port map(
			d => d_s,
			a => a_s,
			iorq_n => iorq_n_s,
			rd_n => rd_n_s,
			wr_n => wr_n_s,
			wait_n => wait_n_s,
			busdir_n => busdir_n_s,
			spi_cs => spi_cs_s,
			spi_sclk => spi_clk_s,
			spi_mosi => spi_mosi_s,
			spi_miso => spi_miso_S,
			spi_rdy => rpi_rdy_s);

	process
	begin

		spi_clk_s <= 'U';
		wr_n_s <= 'U';
		rd_n_s <= 'U';
		iorq_n_s <= 'U';
		wait for 10 fs;
		
		a_s <= x"56";
		d_s <= x"78";
		wr_n_s <= '0';
		rd_n_s <= '1';
		iorq_n_s <= '0';
		wait for 10 fs;
		
		rpi_rdy_s <= '1';
		wait for 10 fs;

	-- Send data to RPi
	-- 8 bits for address, 8 bits for data, wr, rd, iorq = 19 bits
	-- Start transfer cycle

		spi_mosi_s <= '1';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_mosi_s <= '0';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_mosi_s <= '1';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		-- finished send MSX bus
		-- now read 8 bits of data from RPi
		-- simulate RPi taking its time to prepare data
		wait for 50 fs;

		-- read 8 bits data
		spi_miso_s <= '1';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_miso_s <= '0';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_miso_s <= '1';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_miso_s <= '0';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_miso_s <= '1';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_miso_s <= '0';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_miso_s <= '1';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_miso_s <= '0';
		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		-- simulate MSX receiveing data and reseting control signals
		wr_n_s <= '1';
		iorq_n_s <= '1';
		rpi_rdy_s <= '1';

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		spi_clk_s <= '1';
		wait for 10 fs;
		spi_clk_s <= '0';
		wait for 10 fs;

		wait;

	end process;
end;

