------------------------------------------------------------------------------
--  Copyright (c) 2024 by Oliver Bründler, Switzerland
--  All rights reserved.
--  Authors: Oliver Bruendler
------------------------------------------------------------------------------

------------------------------------------------------------------------------
-- Libraries
------------------------------------------------------------------------------
library ieee;
    use ieee.std_logic_1164.all;
    use ieee.numeric_std.all;
    use ieee.math_real.all;

library vunit_lib;
    context vunit_lib.vunit_context;
    context vunit_lib.com_context;
    context vunit_lib.vc_context;

library olo;
    use olo.olo_base_pkg_math.all;
    use olo.olo_base_pkg_logic.all;

------------------------------------------------------------------------------
-- Entity
------------------------------------------------------------------------------
-- vunit: run_all_in_same_sim
entity olo_base_pl_stage_tb is
    generic (
        runner_cfg      : string;
        Stages_g        : natural   := 1;
        UseReady_g      : boolean   := true;
        RandomStall_g   : boolean   := false
    );
end entity olo_base_pl_stage_tb;

architecture sim of olo_base_pl_stage_tb is

    -------------------------------------------------------------------------
    -- Constants
    -------------------------------------------------------------------------
    constant DataWidth_c  : integer := 16;

    -------------------------------------------------------------------------
    -- TB Defnitions
    -------------------------------------------------------------------------
    constant Clk_Frequency_c   : real    := 100.0e6;
    constant Clk_Period_c      : time    := (1 sec) / Clk_Frequency_c;
    -------------------------------------------------------------------------
    -- TB Defnitions
    -------------------------------------------------------------------------
    shared variable InDelay     : time := 0 ns;
    shared variable OutDelay    : time := 0 ns;


    -- *** Verification Compnents ***
    constant axisMaster : axi_stream_master_t := new_axi_stream_master (
        data_length => DataWidth_c,
        stall_config => new_stall_config(choose(RandomStall_g, 0.5, 0.0), 0, 10)
    );
    constant axisSlave : axi_stream_slave_t := new_axi_stream_slave (
        data_length => DataWidth_c,
        stall_config => new_stall_config(choose(RandomStall_g and UseReady_g, 0.5, 0.0), 0, 10)
    );

    -- *** Procedures ***
    procedure Push100 (signal net : inout network_t) is
    begin
        for i in 0 to 99 loop
            wait for InDelay;
            push_axi_stream(net, axisMaster, toUslv(i, DataWidth_c));
        end loop;
    end procedure;

    procedure Check100 (signal net : inout network_t) is
    begin
        for i in 0 to 99 loop
            wait for OutDelay;
            check_axi_stream(net, axisSlave, toUslv(i, DataWidth_c), blocking => false, msg => "data " & integer'image(i));
        end loop;
    end procedure;

    -------------------------------------------------------------------------
    -- Interface Signals
    -------------------------------------------------------------------------
    signal Clk         : std_logic                                      := '0';                              
    signal Rst         : std_logic                                      := '0';    
    signal In_Valid    : std_logic                                      := '0';                              
    signal In_Ready    : std_logic                                      := '0';                              
    signal In_Data     : std_logic_vector(DataWidth_c - 1 downto 0)     := (others => '0'); 
    signal Out_Valid   : std_logic                                      := '0';                              
    signal Out_Ready   : std_logic                                      := '0';                       
    signal Out_Data    : std_logic_vector(DataWidth_c - 1 downto 0)     := (others => '0'); 

begin

    -------------------------------------------------------------------------
    -- TB Control
    -------------------------------------------------------------------------
    -- TB is not very vunit-ish because it is a ported legacy TB
    test_runner_watchdog(runner, 1 ms);
    p_control : process
    begin
        test_runner_setup(runner, runner_cfg);

        while test_suite loop

            InDelay := 0 ns;
            OutDelay := 0 ns;

            -- Reset
            wait until rising_edge(Clk);
            Rst <= '1';
            wait for 1 us;
            wait until rising_edge(Clk);
            Rst <= '0';
            wait until rising_edge(Clk);

            -- Single Word
            if run("Basic") then
                -- One value
                push_axi_stream(net, axisMaster, toUslv(5, DataWidth_c));
                check_axi_stream(net, axisSlave, toUslv(5, DataWidth_c), blocking => false, msg => "data a");
                -- Second value
                wait for 5*Clk_Period_c;
                push_axi_stream(net, axisMaster, toUslv(10, DataWidth_c));
                check_axi_stream(net, axisSlave, toUslv(10, DataWidth_c), blocking => false, msg => "data b");
            end if;

            if run("FullThrottle") then
                Push100(net);
                Check100(net);
            end if;
            
            if run("OutLimited") then
                -- Skip if ready is not implemented (backpressure does not need to be tested in this case)
                if UseReady_g then
                    Push100(net);
                    OutDelay := Clk_Period_c*5;
                    Check100(net);
                end if;
            end if;

            if run("InLimited") then 
                Check100(net);
                InDelay := Clk_Period_c*5;
                Push100(net);
            end if;

            wait for 1 us;
            wait_until_idle(net, as_sync(axisMaster));
            wait_until_idle(net, as_sync(axisSlave));

        end loop;
        -- TB done
        test_runner_cleanup(runner);
    end process;

    -------------------------------------------------------------------------
    -- Clock
    -------------------------------------------------------------------------
    Clk <= not Clk after 0.5*Clk_Period_c;


    -------------------------------------------------------------------------
    -- DUT
    -------------------------------------------------------------------------
    i_dut : entity olo.olo_base_pl_stage
        generic map (
            Width_g       => DataWidth_c,
            UseReady_g    => UseReady_g,
            Stages_g      => Stages_g
        )
        port map (
            Clk         => Clk,     
            Rst         => Rst,    
            In_Valid    => In_Valid,                               
            In_Ready    => In_Ready,   
            In_Data     => In_Data,    
            Out_Valid   => Out_Valid,  
            Out_Ready   => Out_Ready,                       
            Out_Data    => Out_Data
        ); 

    ------------------------------------------------------------
    -- Verification Components
    ------------------------------------------------------------
    vc_stimuli : entity vunit_lib.axi_stream_master
    generic map (
        master => axisMaster
    )
    port map (
        aclk   => Clk,
        tvalid => In_Valid,
        tready => In_Ready,
        tdata  => In_Data
    );
  
    vc_response : entity vunit_lib.axi_stream_slave
    generic map (
        slave => axisSlave
    )
    port map (
        aclk   => Clk,
        tvalid => Out_Valid,
        tready => Out_Ready,
        tdata  => Out_Data   
    );

end sim;
