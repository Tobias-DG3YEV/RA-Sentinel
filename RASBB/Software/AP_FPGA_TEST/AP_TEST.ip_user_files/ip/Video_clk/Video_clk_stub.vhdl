-- Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
-- Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
-- --------------------------------------------------------------------------------
-- Tool Version: Vivado v.2024.2 (win64) Build 5239630 Fri Nov 08 22:35:27 MST 2024
-- Date        : Sun Apr 20 19:47:13 2025
-- Host        : PC1008 running 64-bit major release  (build 9200)
-- Command     : write_vhdl -force -mode synth_stub
--               D:/Data/RASentinel/RASBB/AP-FPGA/AP_TEST/AP_TEST.runs/Video_clk_synth_1/Video_clk_stub.vhdl
-- Design      : Video_clk
-- Purpose     : Stub declaration of top-level module interface
-- Device      : xc7a100tcsg324-2
-- --------------------------------------------------------------------------------
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity Video_clk is
  Port ( 
    o_clk_65M : out STD_LOGIC;
    o_clk_325M : out STD_LOGIC;
    o_clk_195M : out STD_LOGIC;
    o_clk_120M : out STD_LOGIC;
    reset : in STD_LOGIC;
    locked : out STD_LOGIC;
    i_clk_50M : in STD_LOGIC
  );

  attribute CORE_GENERATION_INFO : string;
  attribute CORE_GENERATION_INFO of Video_clk : entity is "Video_clk,clk_wiz_v6_0_15_0_0,{component_name=Video_clk,use_phase_alignment=true,use_min_o_jitter=false,use_max_i_jitter=false,use_dyn_phase_shift=false,use_inclk_switchover=false,use_dyn_reconfig=false,enable_axi=0,feedback_source=FDBK_AUTO,PRIMITIVE=MMCM,num_out_clk=4,clkin1_period=20.000,clkin2_period=10.0,use_power_down=false,use_reset=true,use_locked=true,use_inclk_stopped=false,feedback_type=SINGLE,CLOCK_MGR_TYPE=NA,manual_override=false}";
end Video_clk;

architecture stub of Video_clk is
  attribute syn_black_box : boolean;
  attribute black_box_pad_pin : string;
  attribute syn_black_box of stub : architecture is true;
  attribute black_box_pad_pin of stub : architecture is "o_clk_65M,o_clk_325M,o_clk_195M,o_clk_120M,reset,locked,i_clk_50M";
begin
end;
