library verilog;
use verilog.vl_types.all;
entity MSXPi_vlg_check_tst is
    port(
        BUSDIR_n        : in     vl_logic;
        D               : in     vl_logic_vector(7 downto 0);
        SPI_CS          : in     vl_logic;
        SPI_MOSI        : in     vl_logic;
        WAIT_n          : in     vl_logic;
        sampler_rx      : in     vl_logic
    );
end MSXPi_vlg_check_tst;
