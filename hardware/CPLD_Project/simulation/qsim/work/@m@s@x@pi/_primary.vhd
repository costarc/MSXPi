library verilog;
use verilog.vl_types.all;
entity MSXPi is
    port(
        D               : inout  vl_logic_vector(7 downto 0);
        A               : in     vl_logic_vector(7 downto 0);
        IORQ_n          : in     vl_logic;
        RD_n            : in     vl_logic;
        WR_n            : in     vl_logic;
        BUSDIR_n        : out    vl_logic;
        WAIT_n          : out    vl_logic;
        SPI_CS          : out    vl_logic;
        SPI_SCLK        : in     vl_logic;
        SPI_MOSI        : out    vl_logic;
        SPI_MISO        : in     vl_logic;
        SPI_RDY         : in     vl_logic
    );
end MSXPi;
