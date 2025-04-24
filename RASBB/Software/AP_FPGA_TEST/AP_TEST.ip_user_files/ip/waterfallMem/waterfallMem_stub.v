// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.1.1 (win64) Build 5094488 Fri Jun 14 08:59:21 MDT 2024
// Date        : Wed Jun 26 10:03:31 2024
// Host        : hpelite running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               C:/Data/RASentinel/RASM2400/RASM2400.runs/waterfallMem_synth_1/waterfallMem_stub.v
// Design      : waterfallMem
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7a100tfgg676-1
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* x_core_info = "blk_mem_gen_v8_4_8,Vivado 2024.1" *)
module waterfallMem(clka, wea, addra, dina, clkb, rstb, enb, addrb, doutb, 
  rsta_busy, rstb_busy)
/* synthesis syn_black_box black_box_pad_pin="wea[0:0],addra[17:0],dina[7:0],rstb,enb,addrb[17:0],doutb[7:0],rsta_busy,rstb_busy" */
/* synthesis syn_force_seq_prim="clka" */
/* synthesis syn_force_seq_prim="clkb" */;
  input clka /* synthesis syn_isclock = 1 */;
  input [0:0]wea;
  input [17:0]addra;
  input [7:0]dina;
  input clkb /* synthesis syn_isclock = 1 */;
  input rstb;
  input enb;
  input [17:0]addrb;
  output [7:0]doutb;
  output rsta_busy;
  output rstb_busy;
endmodule
