library verilog;
use verilog.vl_types.all;
entity MSXPi_vlg_sample_tst is
    port(
        A               : in     vl_logic_vector(7 downto 0);
        D               : in     vl_logic_vector(7 downto 0);
        IORQ_n          : in     vl_logic;
        RD_n            : in     vl_logic;
        SPI_MISO        : in     vl_logic;
        SPI_RDY         : in     vl_logic;
        SPI_SCLK        : in     vl_logic;
        WR_n            : in     vl_logic;
        sampler_tx      : out    vl_logic
    );
end MSXPi_vlg_sample_tst;
