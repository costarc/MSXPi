LIBRARY ieee  ; 
LIBRARY std  ; 
USE ieee.NUMERIC_STD.all  ; 
USE ieee.std_logic_1164.all  ; 
USE ieee.std_logic_textio.all  ; 
USE ieee.std_logic_unsigned.all  ; 
USE std.textio.all  ; 
ENTITY msxpi_tb  IS 
END ; 
 
ARCHITECTURE msxpi_tb_arch OF msxpi_tb IS
  SIGNAL SPI_SCLK   :  STD_LOGIC  ; 
  SIGNAL A   :  std_logic_vector (7 downto 0)  ; 
  SIGNAL SPI_RDY   :  STD_LOGIC  ; 
  SIGNAL SPI_MOSI   :  STD_LOGIC  ; 
  SIGNAL SPI_MISO   :  STD_LOGIC  ; 
  SIGNAL D   :  std_logic_vector (7 downto 0)  ; 
  SIGNAL WR_n   :  STD_LOGIC  ; 
  SIGNAL IORQ_n   :  STD_LOGIC  ; 
  SIGNAL SPI_CS   :  STD_LOGIC  ; 
  SIGNAL WAIT_n   :  STD_LOGIC  ; 
  SIGNAL RD_n   :  STD_LOGIC  ; 
  SIGNAL BUSDIR_n   :  STD_LOGIC  ; 
  COMPONENT MSXPi  
    PORT ( 
      SPI_SCLK  : in STD_LOGIC ; 
      A  : in std_logic_vector (7 downto 0) ; 
      SPI_RDY  : in STD_LOGIC ; 
      SPI_MOSI  : out STD_LOGIC ; 
      SPI_MISO  : in STD_LOGIC ; 
      D  : inout std_logic_vector (7 downto 0) ; 
      WR_n  : in STD_LOGIC ; 
      IORQ_n  : in STD_LOGIC ; 
      SPI_CS  : out STD_LOGIC ; 
      WAIT_n  : out STD_LOGIC ; 
      RD_n  : in STD_LOGIC ; 
      BUSDIR_n  : out STD_LOGIC ); 
  END COMPONENT ; 
BEGIN
  DUT  : MSXPi  
    PORT MAP ( 
      SPI_SCLK   => SPI_SCLK  ,
      A   => A  ,
      SPI_RDY   => SPI_RDY  ,
      SPI_MOSI   => SPI_MOSI  ,
      SPI_MISO   => SPI_MISO  ,
      D   => D  ,
      WR_n   => WR_n  ,
      IORQ_n   => IORQ_n  ,
      SPI_CS   => SPI_CS  ,
      WAIT_n   => WAIT_n  ,
      RD_n   => RD_n  ,
      BUSDIR_n   => BUSDIR_n   ) ; 


-- "Constant Pattern"
-- Start Time = 0 ns, End Time = 1 us, Period = 0 ns
  Process
	Begin
	 D  <= x"AA"  ;
	wait for 1000 us ;
-- dumped values till 1 us
	wait;
 End Process;

-- "Constant Pattern"
-- Start Time = 0 ns, End Time = 1 us, Period = 0 ns
  Process
	Begin
	 A  <= x"56"  ;
	wait for 1000 us ;
-- dumped values till 1 us
	wait;
 End Process;
 
-- "Constant Pattern"
-- Start Time = 0 ns, End Time = 1 us, Period = 0 ns
  Process
	Begin
	 iorq_n  <= '0'  ;
	wait for 1000 us ;
-- dumped values till 1 us
	wait;
 End Process;


-- "Constant Pattern"
-- Start Time = 0 ns, End Time = 1 us, Period = 0 ns
  Process
	Begin
	 rd_n  <= '0'  ;
	wait for 1000 us ;
-- dumped values till 1 us
	wait;
 End Process;


-- "Constant Pattern"
-- Start Time = 0 ns, End Time = 1 us, Period = 0 ns
  Process
	Begin
	 wr_n  <= '0'  ;
	wait for 1000 us ;
-- dumped values till 1 us
	wait;
 End Process;


-- "Constant Pattern"
-- Start Time = 0 ns, End Time = 1 us, Period = 0 ns
  Process
	Begin
	 if wait_n  /= ('Z'  ) then 
		report " test case failed" severity error; end if;
	wait for 1000 us ;
-- dumped values till 1 us
	wait;
 End Process;


-- "Constant Pattern"
-- Start Time = 0 ns, End Time = 1 us, Period = 0 ns
  Process
	Begin
	 if spi_cs  /= ('1'  ) then 
		report " test case failed" severity error; end if;
	wait for 1000 us ;
-- dumped values till 1 us
	wait;
 End Process;

-- "Constant Pattern"
-- Start Time = 100 ns, End Time = 1 us, Period = 0 ns
  Process
	Begin
	 spi_miso  <= '0'  ;
	wait for 1 us ;
-- dumped values till 1 us
	wait;
 End Process;


-- "Constant Pattern"
-- Start Time = 50 ns, End Time = 1 us, Period = 0 ns
  Process
	Begin
	 spi_rdy  <= '0'  ;
	wait for 1 us ;
-- dumped values till 1 us
	wait;
 End Process;
END;
