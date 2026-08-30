-- ==============================================================================
-- MSXPi Interface - Version 1.6
-- ==============================================================================
-- MIT License
-- Copyright (c) 2015 - 2026 Ronivon Costa
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
-- Version 0.7R4 - Added msxpi_package, port range 0x56-0x5D
-- Version 1.0   - Firmware version "1001" for PCB v1.0.1; Added /WAIT signal (LED driven by SPI_CS)
-- Version 1.1   - Firmware version "1010" for PCB v1.0.1
-- Version 1.2   - Firmware version "1011" for PCB V1.1, 1.2"
-- Version 1.2.1b- Firmware version "1100", logic optimisation, openMSX support
-- Version 1.3   - Firmware version "1101", more logic optimisation & PLCC AT28C256
-- Version 1.4   - not released (numbering realigned, see below)
-- Version 1.5   - not released (numbering realigned, see below)
-- Version 1.6   - Firmware version "1110", hardware flow control via /WAIT
--                 (WAIT_STATE_SPEC.md), and the SPI engine rebuilt around a
--                 sentinel shift register.  Numbered 1.6 rather than 1.4 so the
--                 CPLD firmware version tracks the BIOS/release version instead
--                 of running on its own sequence - 1.4 and 1.5 are deliberately
--                 skipped and were never released.  MSXPIVer stays "1110": it is
--                 a 4-bit hardware-generation code, not a release number, and
--                 only one value is left in the field.  See
--                 WAIT_STATE_IMPLEMENTATION.md section 4.
-- ==============================================================================

-- ==============================================================================
-- v1.6: HARDWARE FLOW CONTROL VIA /WAIT
-- ------------------------------------------------------------------------------
-- Default OFF.  With the mode register clear this file is behaviourally
-- identical to v1.3 - that equivalence is machine-checked, not asserted: see
-- tb_MSXPi.vhd, which runs this design and MSXPi_v13_reference.vhd side by side
-- off the same stimulus and compares D, BUSDIR_n, SPI_CS and WAIT_n.
--
--   OUT ($57),$01   enable  /WAIT flow control
--   OUT ($57),$00   disable
--   OUT ($56),$FF   reset - also clears the mode (FR-5)
--   IN  ($57)       $0E disabled / $8E enabled
--                   bit 7 = mode, bit 6 = reserved MUST STAY 0 (BC-2 guard,
--                   see the D_out process), bits 5..4 free, bits 3..0 version
--
-- With the mode enabled a plain IN from $5A both starts the SPI transfer and
-- stalls the Z80 until the byte has arrived, so the driver can move a block with
-- INIR/OTIR instead of the ~330 T-state CHKPIRDY poll per byte.
--
-- READ THIS BEFORE ENABLING IT ON HARDWARE
-- ----------------------------------------
-- There is no free-running clock on this CPLD; the only clock is SPI_SCLK, which
-- the Pi drives.  Two consequences that no amount of RTL can remove:
--
--   1. The stall lasts exactly as long as the Pi takes for one byte.  The
--      bit-banged Python SPI_ByteTransfer() in msxpi-server.py needs 200-600 us,
--      which is 10-30x the ~20 us ceiling in SR-3 and long enough to disturb
--      interrupt latency and Z80-refresh-driven DRAM.  The Pi-side SPI rewrite
--      is a prerequisite for enabling this mode, not a follow-up to it.
--
--   2. If the Pi stops clocking mid-byte, only SPI_RDY can end the stall.  That
--      covers Ctrl-C and any clean exit, because msxpi-server.py calls
--      GPIO.cleanup() and R8 (10K to GND on the SPI_RDY net) then pulls the line
--      low, which releases /WAIT combinationally with no clock at all.  It does
--      NOT cover kill -9, where the pad keeps its last level: /WAIT stays
--      asserted and the MSX hangs until power-cycled.  Closing that last hole
--      needs a real clock - one wire from J1 pin 42 (CLOCK, already on the
--      cartridge connector and currently routed nowhere) to U2 pin 43 (GCLK1,
--      currently unconnected).  See WAIT_STATE_IMPLEMENTATION.md.
-- ==============================================================================

-- ==============================================================================
-- Libraries
-- ==============================================================================
library ieee;
use ieee.std_logic_1164.all;
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

    -- Control signals
    signal readoper         : std_logic;
    signal writeoper        : std_logic;
    signal spi_en           : std_logic;
    signal RESET            : std_logic;

    -- Data buffers
    signal D_buff_msx       : std_logic_vector(7 downto 0);
    signal D_out            : std_logic_vector(7 downto 0);

    -- Sentinel shift register.  Replaces v1.3's D_buff_pi + bitcount + the
    -- three-state FSM with one register.  It is loaded with a single '1' at
    -- bit 0 when a transfer starts; MISO shifts in at the bottom, so every
    -- received bit stays BELOW the sentinel and every bit above it is still
    -- zero.  The sentinel is therefore always the highest set bit, which makes
    -- both the phase tests free of any counter:
    --      pi_sr(9 downto 1) = 0   ->  nothing received yet, this edge is E1
    --      pi_sr(9)          = '1' ->  all eight bits are in, byte complete
    -- and the received byte is simply pi_sr(7 downto 0).
    signal pi_sr            : std_logic_vector(9 downto 0) := (others => '0');
    signal msx_sr           : std_logic_vector(7 downto 0);

    -- SPI control
    signal SPI_en_s         : std_logic := '0';
    signal SPI_RDY_s        : std_logic;

    -- Address decode helpers
    signal is_ctrl_or_data  : std_logic;
    signal is_data          : std_logic;

    -- /WAIT support
    signal wait_mode        : std_logic := '0';
    signal wr_ctrl2         : std_logic;
    signal wait_clr         : std_logic;
    signal started          : std_logic := '0';
    signal wait_assert      : std_logic;

begin

    -- ==========================================================================
    -- Port Decoding and Control
    -- ==========================================================================
    is_ctrl_or_data <= '1' when A = CTRLPORT1 or A = DATAPORT1 else '0';
    is_data         <= '1' when A = DATAPORT1 else '0';

    -- BUSDIR_n is deliberately left exactly as v1.3 had it, so BC-1 holds to the
    -- letter.  Spec open question 2 is nonetheless correct: not asserting it for
    -- reads of CTRLPORT2 is a latent bug on expanded slots, and msxpi_bios.asm:97
    -- reads $57 to tell real hardware from openMSX, so that read can return
    -- garbage behind a slot expander.  The fix is the commented line below and it
    -- is free - measured at 44/64 macrocells against 45/64 without it, because
    -- "A is one of $56/$57/$5A" decodes more cheaply than the same set with $57
    -- carved out.  It is off by default only because it changes legacy behaviour
    -- and therefore needs its own regression pass on real hardware.
    BUSDIR_n     <= '0' when (readoper = '1' and is_ctrl_or_data = '1') else '1';
--  BUSDIR_n     <= '0' when (readoper = '1' and
--                            (is_ctrl_or_data = '1' or A = CTRLPORT2)) else '1';
    readoper     <= not (IORQ_n or RD_n);
    writeoper    <= not (IORQ_n or WR_n);

    -- SPI status logic
    SPI_RDY_s    <= SPI_en_s or (not SPI_RDY);

    -- Reset condition
    RESET        <= '1' when (writeoper = '1' and A = CTRLPORT1 and D = x"FF") else '0';

    -- MSX write buffer.  Deliberately a transparent latch: D is only valid
    -- while the write cycle is on the bus, and there is no clock at that moment
    -- to register it with.  It is also what makes a /WAIT-stretched OTIR write
    -- safe - the Z80 holds D for the whole stretched cycle, so the E1 edge
    -- below samples a stable value however long the stall lasted.
    D_buff_msx   <= D when (writeoper = '1' and is_ctrl_or_data = '1');

    -- ==========================================================================
    -- /WAIT mode register (FR-3..FR-5)
    -- Async set / async clear: there is no clock at the instant the MSX writes
    -- the port, so this is an SR latch by construction, not by accident.
    -- Power-up state is '0' - legacy behaviour (FR-3).
    -- ==========================================================================
    -- This MUST synthesise to a real register with an asynchronous clear, NOT to
    -- a latch.  Writing it as a plain async set/reset pair infers a latch whose
    -- enable is tied to GND, which on MAX3000A has no guaranteed power-up state -
    -- and a VHDL ":= '0'" initialiser does nothing about that, it only fools the
    -- simulator.  An early revision did that and the device powered up already in
    -- WAIT mode: every IN ($5A) fired an extra transfer and the byte stream
    -- desynchronised permanently.
    --
    -- Clocking it on the port-write strobe makes it an ordinary control register,
    -- and the device's power-on reset clears registers.  Check this after any
    -- edit: "wait_mode" must NOT appear in the "User-Specified and Inferred
    -- Latches" table of MSXPi.map.rpt.
    --
    -- 'started' is the same construct but is self-correcting - its clear is
    -- spi_en = '0', which holds whenever the bus is idle - so it settles within
    -- nanoseconds of power-up whatever state it comes up in.
    wr_ctrl2 <= '1' when (writeoper = '1' and A = CTRLPORT2) else '0';

    wait_clr <= '1' when (RESET = '1') or
                         (writeoper = '1' and A = CTRLPORT2 and D = WAITMODE_OFF) else '0';

    mode_reg: process(wait_clr, wr_ctrl2)
    begin
        if wait_clr = '1' then
            wait_mode <= '0';
        elsif rising_edge(wr_ctrl2) then
            -- Only $01 sets it; every other value is a no-op (FR-4).  $00 is
            -- handled by the asynchronous clear above.
            if D = WAITMODE_ON then
                wait_mode <= '1';
            end if;
        end if;
    end process;

    -- ==========================================================================
    -- Transfer start
    -- ==========================================================================
    -- spi_en MUST stay at exactly the same logic depth as RESET (one level below
    -- writeoper).  If it is even one gate slower, the end of a reset write -
    -- RESET falling before spi_en - opens the async-set guard below for a few ns
    -- and kicks off a spurious transfer.  Hence one flat expression here, with
    -- the anti-retrigger guard moved into the FSM condition instead.
    --
    -- SR-2: the read-triggered start is additionally gated on SPI_RDY.  Without
    -- it, an INIR read issued while the Pi is absent would still arm a transfer
    -- that nobody clocks; when the server came back it would service that stale
    -- transfer and the byte stream would be permanently one byte out of step.
    -- With the gate, a read with no Pi present is a plain read of the stale
    -- buffer - exactly what legacy mode does - and the checksum/retry layer
    -- above catches it.
    --
    -- With wait_mode = '0' the second disjunct is constantly '0', so this
    -- reduces to the v1.3 expression (BC-1).
    spi_en <= '1' when (writeoper = '1' and is_ctrl_or_data = '1') or
                       (wait_mode = '1' and readoper = '1' and is_data = '1'
                                        and SPI_RDY = '1') else '0';

    -- 'started' stops one stretched I/O cycle from kicking off a second transfer
    -- the instant SPI_en_s drops.  In legacy mode the access is always over long
    -- before the transfer completes, so this never engages.
    start_lat: process(spi_en, SPI_en_s)
    begin
        if spi_en = '0' then
            started <= '0';
        elsif SPI_en_s = '1' then
            started <= '1';
        end if;
    end process;

    -- ==========================================================================
    -- /WAIT driver (FR-1, FR-2)
    -- Open-collector style: driven low or released, never driven high.
    -- SPI_RDY is in the term on purpose - see the header note.
    -- ==========================================================================
    wait_assert <= wait_mode and SPI_RDY and spi_en and (SPI_en_s or (not started));
    WAIT_n      <= '0' when wait_assert = '1' else 'Z';

    -- ==========================================================================
    -- D Bus Output Logic
    -- ==========================================================================
    process(A, SPI_RDY_s, pi_sr, wait_mode)
    begin
        if A = CTRLPORT1 then
            D_out <= "0000000" & SPI_RDY_s;
        elsif A = DATAPORT1 then
            D_out <= pi_sr(7 downto 0);
        elsif A = CTRLPORT2 then
            -- $0E disabled, $1E enabled.  Both stay below $FE, which
            -- msxpi_bios.asm:97 relies on to tell real hardware from openMSX.
            -- $57 layout:
            --   bit 7    wait_mode read-back
            --   bit 6    RESERVED - MUST STAY '0'.  This is a backward-compat
            --            guard, not spare space.  msxpi_bios.asm:97 detects
            --            openMSX by testing $57 against $FE, so $57 must never
            --            reach $FE/$FF (BC-2).  MSXPIVer is already "1110", so
            --            with bit 7 set, allocating bits 6..4 and setting them
            --            all would produce exactly $FE and break detection in
            --            the field.  Holding bit 6 at '0' caps the port at $BF
            --            for ever, whatever bits 5..0 are later used for.
            --   bits 5-4 free for future use
            --   bits 3-0 MSXPIVer
            -- Reads $0E with the mode off, $8E with it on.
            D_out <= wait_mode & '0' & "00" & MSXPIVer;
        else
            D_out <= (others => 'Z');
        end if;
    end process;

    D <= D_out when readoper = '1' else (others => 'Z');

    -- ==========================================================================
    -- SPI Serialization & Transfer Process
    -- ------------------------------------------------------------------------
    -- Edge map, unchanged from v1.3 and matching msxpi-server.py exactly:
    --   E1        leading  tick_sclk()  -> load msx_sr from the write latch
    --   E2 .. E9  the eight data bits   -> MOSI out, MISO in
    --   E10       trailing tick_sclk()  -> drop SPI_en_s, raise SPI_CS
    -- ==========================================================================
    spi: process(RESET, SPI_SCLK, SPI_en_s, spi_en)
    begin
        if RESET = '1' then
            SPI_en_s <= '0';
            pi_sr    <= (others => '0');       -- reads back $00, as v1.3 did

        elsif (SPI_en_s = '0' and spi_en = '1' and started = '0') then
            SPI_en_s <= '1';
            pi_sr    <= "0000000001";          -- sentinel at bit 0

        elsif rising_edge(SPI_SCLK) then
            if SPI_en_s = '1' then
                if pi_sr(9) = '1' then                     -- E10
                    SPI_en_s <= '0';
                else
                    pi_sr <= pi_sr(8 downto 0) & SPI_MISO;
                    if pi_sr(9 downto 1) = "000000000" then -- E1
                        msx_sr <= D_buff_msx;
                    else                                    -- E2 .. E9
                        SPI_MOSI <= msx_sr(7);
                        msx_sr   <= msx_sr(6 downto 0) & '0';
                    end if;
                end if;
            end if;
        end if;

        SPI_CS <= not SPI_en_s;
    end process;

end rtl;
