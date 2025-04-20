// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.2 (win64) Build 5239630 Fri Nov 08 22:35:27 MST 2024
// Date        : Sun Apr 20 19:47:13 2025
// Host        : PC1008 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               D:/Data/RASentinel/RASBB/AP-FPGA/AP_TEST/AP_TEST.runs/Video_clk_synth_1/Video_clk_stub.v
// Design      : Video_clk
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a100tcsg324-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* CORE_GENERATION_INFO = "Video_clk,clk_wiz_v6_0_15_0_0,{component_name=Video_clk,use_phase_alignment=true,use_min_o_jitter=false,use_max_i_jitter=false,use_dyn_phase_shift=false,use_inclk_switchover=false,use_dyn_reconfig=false,enable_axi=0,feedback_source=FDBK_AUTO,PRIMITIVE=MMCM,num_out_clk=4,clkin1_period=20.000,clkin2_period=10.0,use_power_down=false,use_reset=true,use_locked=true,use_inclk_stopped=false,feedback_type=SINGLE,CLOCK_MGR_TYPE=NA,manual_override=false}" *) 
module Video_clk(o_clk_65M, o_clk_325M, o_clk_195M, o_clk_120M, 
  reset, locked, i_clk_50M)
/* synthesis syn_black_box black_box_pad_pin="reset,locked,i_clk_50M" */
/* synthesis syn_force_seq_prim="o_clk_65M" */
/* synthesis syn_force_seq_prim="o_clk_325M" */
/* synthesis syn_force_seq_prim="o_clk_195M" */
/* synthesis syn_force_seq_prim="o_clk_120M" */;
  output o_clk_65M /* synthesis syn_isclock = 1 */;
  output o_clk_325M /* synthesis syn_isclock = 1 */;
  output o_clk_195M /* synthesis syn_isclock = 1 */;
  output o_clk_120M /* synthesis syn_isclock = 1 */;
  input reset;
  output locked;
  input i_clk_50M;
endmodule
