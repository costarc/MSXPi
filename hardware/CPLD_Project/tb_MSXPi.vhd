-- Differential testbench: v1.3 reference vs v1.6 (shift-register) DUT.
-- The Pi model reproduces msxpi-server.py SPI_ByteTransfer() exactly:
--   RDY high -> spin until CS low -> tick -> 8 bit clocks -> tick -> RDY low
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.msxpi_package.all;

entity tb_MSXPi is
end tb_MSXPi;

architecture sim of tb_MSXPi is

    signal A        : std_logic_vector(7 downto 0) := (others => '0');
    signal IORQ_n   : std_logic := '1';
    signal RD_n     : std_logic := '1';
    signal WR_n     : std_logic := '1';
    signal SPI_SCLK : std_logic := '0';
    signal SPI_MISO : std_logic := '0';
    signal SPI_RDY  : std_logic := '0';

    signal D13, D14 : std_logic_vector(7 downto 0) := (others => 'Z');
    signal BUSDIR13, BUSDIR14 : std_logic;
    signal WAIT13,   WAIT14   : std_logic;
    signal CS13,     CS14     : std_logic;
    signal MOSI13,   MOSI14   : std_logic;

    signal compare_en : boolean := true;
    signal errors     : integer := 0;   -- driven by the equivalence checker only
    signal errors2    : integer := 0;   -- driven by the stimulus process only
    signal checks     : integer := 0;

    -- Pi model control
    signal pi_run     : boolean := false;
    signal pi_tx      : std_logic_vector(7 downto 0) := x"00";
    signal pi_rx13    : std_logic_vector(7 downto 0) := x"00";
    signal pi_rx14    : std_logic_vector(7 downto 0) := x"00";
    signal pi_bytes   : integer := 0;
    signal pi_abort   : boolean := false;   -- server killed (Ctrl-C -> GPIO.cleanup)
    signal pi_watch14 : boolean := false;   -- which DUT's SPI_CS the Pi follows
    signal pi_sigkill : boolean := false;   -- kill -9: GPIO pads keep their state,
                                           -- so SPI_RDY stays HIGH and SCLK stops

    constant TS      : time := 279 ns;      -- one Z80 T-state at 3.58 MHz
    constant PI_HALF : time := 1 us;        -- Pi bit-bang half period

begin

    dut13: entity work.MSXPi_v13 port map(
        D=>D13, A=>A, IORQ_n=>IORQ_n, RD_n=>RD_n, WR_n=>WR_n,
        BUSDIR_n=>BUSDIR13, WAIT_n=>WAIT13, SPI_CS=>CS13,
        SPI_SCLK=>SPI_SCLK, SPI_MOSI=>MOSI13, SPI_MISO=>SPI_MISO, SPI_RDY=>SPI_RDY);

    dut16: entity work.MSXPi_v16 port map(
        D=>D14, A=>A, IORQ_n=>IORQ_n, RD_n=>RD_n, WR_n=>WR_n,
        BUSDIR_n=>BUSDIR14, WAIT_n=>WAIT14, SPI_CS=>CS14,
        SPI_SCLK=>SPI_SCLK, SPI_MOSI=>MOSI14, SPI_MISO=>SPI_MISO, SPI_RDY=>SPI_RDY);

    -- ----------------------------------------------------------------------
    -- Continuous equivalence checker (legacy mode only)
    -- ----------------------------------------------------------------------
    chk: process
    begin
        loop
            wait for 37 ns;
            if compare_en then
                checks <= checks + 1;
                if D13 /= D14 then
                    report "MISMATCH D: v13=" & to_hstring(D13) & " v16=" & to_hstring(D14)
                        severity error;
                    errors <= errors + 1;
                end if;
                if BUSDIR13 /= BUSDIR14 then
                    report "MISMATCH BUSDIR" severity error;
                    errors <= errors + 1;
                end if;
                if CS13 /= CS14 then
                    report "MISMATCH SPI_CS" severity error;
                    errors <= errors + 1;
                end if;
                if WAIT13 /= WAIT14 then
                    report "MISMATCH WAIT_n (legacy must be Z on both)" severity error;
                    errors <= errors + 1;
                end if;
            end if;
        end loop;
    end process;

    -- ----------------------------------------------------------------------
    -- Raspberry Pi model
    -- ----------------------------------------------------------------------
    pi: process
        variable b13, b14 : std_logic_vector(7 downto 0);
    begin
        SPI_RDY  <= '0';
        SPI_SCLK <= '0';
        wait until pi_run;
        loop
            exit when not pi_run;
            SPI_RDY <= '1';
            loop
                exit when ((CS13 = '0') and not pi_watch14)
                       or ((CS14 = '0') and pi_watch14)
                       or (not pi_run) or pi_abort;
                wait for 200 ns;
            end loop;
            if pi_abort then
                -- Ctrl-C / clean exit: GPIO.cleanup() releases the pad and the
                -- R8 10K pulldown takes SPI_RDY low.  Recoverable: the server
                -- can be restarted, so wait here rather than dying.
                SPI_RDY <= '0';
                wait until not pi_abort;
                next;
            end if;
            if pi_sigkill then
                -- kill -9: no cleanup runs, the pad keeps its last level, so
                -- SPI_RDY stays HIGH and SCLK simply stops for ever.
                SPI_RDY <= '1';
                wait;
            end if;
            exit when not pi_run;

            SPI_SCLK <= '1'; wait for PI_HALF; SPI_SCLK <= '0'; wait for PI_HALF;

            for i in 7 downto 0 loop
                SPI_MISO <= pi_tx(i);
                wait for 50 ns;
                SPI_SCLK <= '1';
                wait for PI_HALF;
                b13(i) := MOSI13;
                b14(i) := MOSI14;
                SPI_SCLK <= '0';
                wait for PI_HALF;
            end loop;

            SPI_SCLK <= '1'; wait for PI_HALF; SPI_SCLK <= '0'; wait for PI_HALF;

            SPI_RDY  <= '0';
            pi_rx13  <= b13;
            pi_rx14  <= b14;
            pi_bytes <= pi_bytes + 1;
            wait for 2 us;
        end loop;
        wait;
    end process;

    -- ----------------------------------------------------------------------
    -- MSX side
    -- ----------------------------------------------------------------------
    stim: process

        procedure io_write(port_a : std_logic_vector(7 downto 0);
                           val    : std_logic_vector(7 downto 0)) is
        begin
            A   <= port_a;
            D13 <= val;  D14 <= val;
            wait for TS;
            IORQ_n <= '0'; WR_n <= '0';
            wait for 2*TS;
            IORQ_n <= '1'; WR_n <= '1';
            wait for TS;
            D13 <= (others => 'Z'); D14 <= (others => 'Z');
            wait for TS;
        end procedure;

        procedure io_read(port_a : std_logic_vector(7 downto 0);
                          got13  : out std_logic_vector(7 downto 0);
                          got14  : out std_logic_vector(7 downto 0)) is
        begin
            A <= port_a;
            wait for TS;
            IORQ_n <= '0'; RD_n <= '0';
            wait for 2*TS;
            got13 := D13; got14 := D14;
            IORQ_n <= '1'; RD_n <= '1';
            wait for 2*TS;
        end procedure;

        -- WAIT-aware read: honours WAIT14 the way a real Z80 does
        procedure io_read_wait(port_a  : std_logic_vector(7 downto 0);
                               got     : out std_logic_vector(7 downto 0);
                               stalled : out time) is
            variable t0 : time;
        begin
            A <= port_a;
            wait for TS;                 -- T1
            IORQ_n <= '0'; RD_n <= '0';  -- T2
            wait for TS;
            t0 := now;
            wait for TS;                 -- TW (automatic I/O wait state)
            while WAIT14 = '0' loop
                wait for TS;
            end loop;
            stalled := now - t0;
            got := D14;                  -- data sampled at the end of T3
            IORQ_n <= '1'; RD_n <= '1';
            wait for 2*TS;
        end procedure;

        variable g13, g14 : std_logic_vector(7 downto 0);
        variable st       : time;
        variable expect   : std_logic_vector(7 downto 0);
    begin
        wait for 1 us;

        report "=== PHASE 1: legacy mode, v1.6 must match v1.3 exactly ===";
        pi_run <= true;
        wait for 1 us;

        io_write(CTRLPORT1, x"FF");
        wait for 5 us;

        io_read(CTRLPORT2, g13, g14);
        assert g13 = g14 report "version read differs" severity error;
        report "  port $57 legacy reads " & to_hstring(g14);
        assert g14 = x"0E" report "port $57 must read $0E (BC-2)" severity error;

        for k in 0 to 3 loop
            expect := std_logic_vector(to_unsigned(16#5A# + k*17, 8));
            pi_tx <= expect;
            wait for 1 us;
            io_read(CTRLPORT1, g13, g14);
            io_write(CTRLPORT1, x"00");
            wait for 40 us;
            io_read(DATAPORT1, g13, g14);
            assert g13 = g14
                report "PHASE1 data mismatch v13=" & to_hstring(g13) & " v16=" & to_hstring(g14)
                severity error;
            assert g14 = expect
                report "PHASE1 wrong byte: got " & to_hstring(g14) & " want " & to_hstring(expect)
                severity error;
            report "  rx byte " & to_hstring(g14) & " OK (v13=v16)";
        end loop;

        for k in 0 to 3 loop
            expect := std_logic_vector(to_unsigned(16#C3# - k*9, 8));
            io_write(DATAPORT1, expect);
            wait for 40 us;
            assert pi_rx13 = pi_rx14
                report "PHASE1 MOSI mismatch v13=" & to_hstring(pi_rx13)
                     & " v16=" & to_hstring(pi_rx14) severity error;
            assert pi_rx14 = expect
                report "PHASE1 Pi got " & to_hstring(pi_rx14) & " want " & to_hstring(expect)
                severity error;
            report "  tx byte " & to_hstring(pi_rx14) & " OK (v13=v16)";
        end loop;

        io_read(DATAPORT1, g13, g14);
        assert CS13 = '1' and CS14 = '1'
            report "BC-1 VIOLATION: legacy read of $5A started a transfer" severity error;
        report "  legacy read of $5A does not start a transfer: OK";
        report "PHASE 1 complete, errors so far = " & integer'image(errors + errors2);

        report "=== PHASE 2: WAIT mode ===";
        compare_en <= false;      -- v1.3 has no WAIT mode to compare against
        pi_watch14 <= true;       -- only v1.6 drives CS for a read-started transfer
        wait for 1 us;

        io_write(CTRLPORT2, x"01");
        wait for 2 us;
        io_read(CTRLPORT2, g13, g14);
        report "  port $57 in WAIT mode reads " & to_hstring(g14);
        assert g14 = x"8E" report "mode bit not readable at $57 bit 7" severity error;
        assert g14 < x"FE" report "BC-2 VIOLATION: $57 reached $FE/$FF" severity error;

        for k in 0 to 3 loop
            expect := std_logic_vector(to_unsigned(16#11# + k*32, 8));
            pi_tx <= expect;
            wait for 4 us;
            io_read_wait(DATAPORT1, g14, st);
            report "  inir read -> " & to_hstring(g14) & "  stalled " & time'image(st);
            assert g14 = expect
                report "WAIT-mode read: got " & to_hstring(g14) & " want " & to_hstring(expect)
                severity error;
            assert st > 0 ns report "no stall: /WAIT never asserted" severity error;
        end loop;

        io_write(DATAPORT1, x"7E");
        wait for 40 us;
        assert pi_rx14 = x"7E"
            report "WAIT-mode write: Pi got " & to_hstring(pi_rx14) severity error;
        report "  otir write $7E -> Pi received " & to_hstring(pi_rx14) & " OK";

        report "=== PHASE 3: FR-5, reset clears the mode ===";
        io_write(CTRLPORT1, x"FF");
        wait for 25 us;
        io_read(CTRLPORT2, g13, g14);
        report "  port $57 after reset reads " & to_hstring(g14);
        assert g14 = x"0E" report "FR-5 VIOLATION: reset did not clear WAIT mode" severity error;

        io_read(DATAPORT1, g13, g14);
        assert CS14 = '1' report "FR-5 VIOLATION: still in WAIT mode" severity error;
        report "  reset restored legacy behaviour: OK";

        report "=== PHASE 4: SR-2 safety, server dies ===";
        io_write(CTRLPORT2, x"01");
        wait for 2 us;
        pi_abort <= true;
        wait for 6 us;

        A <= DATAPORT1;
        wait for TS;
        IORQ_n <= '0'; RD_n <= '0';
        wait for 3*TS;
        assert WAIT14 /= '0'
            report "HANG RISK: /WAIT asserted while SPI_RDY is low" severity error;
        report "  /WAIT stays released when the Pi is gone: OK";
        if CS14 = '0' then
            report "SR-2 VIOLATION: a transfer was armed with no Pi present"
                severity error;
            errors2 <= errors2 + 1;
        else
            report "  and no stale transfer was armed: OK";
        end if;
        IORQ_n <= '1'; RD_n <= '1';
        wait for 2*TS;

        report "=== PHASE 5: soak, 32 bytes each way through the /WAIT path ===";
        pi_abort <= false;
        wait for 5 us;
        io_write(CTRLPORT2, x"01");
        wait for 2 us;
        for k in 0 to 31 loop
            expect := std_logic_vector(to_unsigned((k*37 + 19) mod 256, 8));
            pi_tx <= expect;
            wait for 4 us;
            io_read_wait(DATAPORT1, g14, st);
            if g14 /= expect then
                report "SOAK rx " & integer'image(k) & ": got " & to_hstring(g14)
                     & " want " & to_hstring(expect) severity error;
                errors2 <= errors2 + 1;
            end if;
        end loop;
        report "  32 inir reads verified";

        for k in 0 to 31 loop
            expect := std_logic_vector(to_unsigned((k*53 + 7) mod 256, 8));
            io_write(DATAPORT1, expect);
            wait for 40 us;
            if pi_rx14 /= expect then
                report "SOAK tx " & integer'image(k) & ": Pi got " & to_hstring(pi_rx14)
                     & " want " & to_hstring(expect) severity error;
                errors2 <= errors2 + 1;
            end if;
        end loop;
        report "  32 otir writes verified";

        report "=== PHASE 6: residual risk, kill -9 (RDY stuck high, SCLK stops) ===";
        pi_sigkill <= true;
        wait for 10 us;
        A <= DATAPORT1;
        wait for TS;
        IORQ_n <= '0'; RD_n <= '0';
        wait for 200 us;
        if WAIT14 = '0' then
            report "  CONFIRMED: /WAIT still asserted after 200 us - the MSX is hung."
                 & " There is no clock left to time out on.  This is the one case a"
                 & " free-running clock input would fix." severity note;
        else
            report "  /WAIT released - unexpected, investigate" severity error;
            errors2 <= errors2 + 1;
        end if;
        IORQ_n <= '1'; RD_n <= '1';
        wait for 2*TS;

        pi_run <= false;
        wait for 2 us;
        report "==================================================";
        report "CHECKS RUN  : " & integer'image(checks);
        report "TOTAL ERRORS: " & integer'image(errors + errors2);
        report "==================================================";
        assert errors + errors2 = 0 report "DIFFERENTIAL TEST FAILED" severity failure;
        report "ALL TESTS PASSED" severity note;
        std.env.stop;
    end process;

end sim;
