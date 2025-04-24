// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2025 Advanced Micro Devices, Inc. All Rights Reserved.
// -------------------------------------------------------------------------------

`timescale 1 ps / 1 ps

(* BLOCK_STUB = "true" *)
module xfft_v9 (
  aclk,
  aresetn,
  s_axis_config_tdata,
  s_axis_config_tvalid,
  s_axis_config_tready,
  s_axis_data_tdata,
  s_axis_data_tvalid,
  s_axis_data_tready,
  s_axis_data_tlast,
  m_axis_data_tdata,
  m_axis_data_tvalid,
  m_axis_data_tready,
  m_axis_data_tlast,
  event_frame_started,
  event_tlast_unexpected,
  event_tlast_missing,
  event_status_channel_halt,
  event_data_in_channel_halt,
  event_data_out_channel_halt
);

  (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk_intf CLK" *)
  (* X_INTERFACE_MODE = "slave aclk_intf" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aclk_intf, ASSOCIATED_BUSIF S_AXIS_CONFIG:M_AXIS_DATA:M_AXIS_STATUS:S_AXIS_DATA, ASSOCIATED_RESET aresetn, ASSOCIATED_CLKEN aclken, FREQ_HZ 100000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, CLK_DOMAIN , ASSOCIATED_PORT , INSERT_VIP 0" *)
  input aclk;
  (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn_intf RST" *)
  (* X_INTERFACE_MODE = "slave aresetn_intf" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME aresetn_intf, POLARITY ACTIVE_LOW, INSERT_VIP 0" *)
  input aresetn;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_CONFIG TDATA" *)
  (* X_INTERFACE_MODE = "slave S_AXIS_CONFIG" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXIS_CONFIG, TDATA_NUM_BYTES 1, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 0, FREQ_HZ 100000000, PHASE 0.0, CLK_DOMAIN , LAYERED_METADATA undef, INSERT_VIP 0" *)
  input [7:0]s_axis_config_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_CONFIG TVALID" *)
  input s_axis_config_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_CONFIG TREADY" *)
  output s_axis_config_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_DATA TDATA" *)
  (* X_INTERFACE_MODE = "slave S_AXIS_DATA" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S_AXIS_DATA, TDATA_NUM_BYTES 4, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 1, FREQ_HZ 100000000, PHASE 0.0, CLK_DOMAIN , LAYERED_METADATA undef, INSERT_VIP 0" *)
  input [31:0]s_axis_data_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_DATA TVALID" *)
  input s_axis_data_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_DATA TREADY" *)
  output s_axis_data_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 S_AXIS_DATA TLAST" *)
  input s_axis_data_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_DATA TDATA" *)
  (* X_INTERFACE_MODE = "master M_AXIS_DATA" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M_AXIS_DATA, TDATA_NUM_BYTES 6, TDEST_WIDTH 0, TID_WIDTH 0, TUSER_WIDTH 0, HAS_TREADY 1, HAS_TSTRB 0, HAS_TKEEP 0, HAS_TLAST 1, FREQ_HZ 100000000, PHASE 0.0, CLK_DOMAIN , LAYERED_METADATA undef, INSERT_VIP 0" *)
  output [47:0]m_axis_data_tdata;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_DATA TVALID" *)
  output m_axis_data_tvalid;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_DATA TREADY" *)
  input m_axis_data_tready;
  (* X_INTERFACE_INFO = "xilinx.com:interface:axis:1.0 M_AXIS_DATA TLAST" *)
  output m_axis_data_tlast;
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 event_frame_started_intf INTERRUPT" *)
  (* X_INTERFACE_MODE = "master event_frame_started_intf" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME event_frame_started_intf, SENSITIVITY EDGE_RISING, PortWidth 1" *)
  output event_frame_started;
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 event_tlast_unexpected_intf INTERRUPT" *)
  (* X_INTERFACE_MODE = "master event_tlast_unexpected_intf" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME event_tlast_unexpected_intf, SENSITIVITY EDGE_RISING, PortWidth 1" *)
  output event_tlast_unexpected;
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 event_tlast_missing_intf INTERRUPT" *)
  (* X_INTERFACE_MODE = "master event_tlast_missing_intf" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME event_tlast_missing_intf, SENSITIVITY EDGE_RISING, PortWidth 1" *)
  output event_tlast_missing;
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 event_status_channel_halt_intf INTERRUPT" *)
  (* X_INTERFACE_MODE = "master event_status_channel_halt_intf" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME event_status_channel_halt_intf, SENSITIVITY EDGE_RISING, PortWidth 1" *)
  output event_status_channel_halt;
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 event_data_in_channel_halt_intf INTERRUPT" *)
  (* X_INTERFACE_MODE = "master event_data_in_channel_halt_intf" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME event_data_in_channel_halt_intf, SENSITIVITY EDGE_RISING, PortWidth 1" *)
  output event_data_in_channel_halt;
  (* X_INTERFACE_INFO = "xilinx.com:signal:interrupt:1.0 event_data_out_channel_halt_intf INTERRUPT" *)
  (* X_INTERFACE_MODE = "master event_data_out_channel_halt_intf" *)
  (* X_INTERFACE_PARAMETER = "XIL_INTERFACENAME event_data_out_channel_halt_intf, SENSITIVITY EDGE_RISING, PortWidth 1" *)
  output event_data_out_channel_halt;

  // stub module has no contents

endmodule
