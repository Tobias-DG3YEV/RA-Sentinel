// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.2 (win64) Build 5239630 Fri Nov 08 22:35:27 MST 2024
// Date        : Mon Feb 24 03:43:35 2025
// Host        : PC1008 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               d:/Data/RASentinel/RASBB/AP-FPGA/AP_FPGA/AP_FPGA.srcs/sources_1/openwifi/rot_lut/rot_lut_sim_netlist.v
// Design      : rot_lut
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7a100tcsg324-2
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "rot_lut,blk_mem_gen_v8_4_9,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_9,Vivado 2024.2" *) 
(* NotValidForBitStream *)
module rot_lut
   (clka,
    addra,
    douta,
    clkb,
    enb,
    addrb,
    doutb);
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) (* x_interface_mode = "slave BRAM_PORTA" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTA, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clka;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [8:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *) output [31:0]douta;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_mode = "slave BRAM_PORTB" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *) input enb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [8:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [31:0]doutb;

  wire [8:0]addra;
  wire [8:0]addrb;
  wire clka;
  wire [31:0]douta;
  wire [31:0]doutb;
  wire enb;
  wire NLW_U0_dbiterr_UNCONNECTED;
  wire NLW_U0_rsta_busy_UNCONNECTED;
  wire NLW_U0_rstb_busy_UNCONNECTED;
  wire NLW_U0_s_axi_arready_UNCONNECTED;
  wire NLW_U0_s_axi_awready_UNCONNECTED;
  wire NLW_U0_s_axi_bvalid_UNCONNECTED;
  wire NLW_U0_s_axi_dbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_rlast_UNCONNECTED;
  wire NLW_U0_s_axi_rvalid_UNCONNECTED;
  wire NLW_U0_s_axi_sbiterr_UNCONNECTED;
  wire NLW_U0_s_axi_wready_UNCONNECTED;
  wire NLW_U0_sbiterr_UNCONNECTED;
  wire [8:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [8:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [31:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "9" *) 
  (* C_ADDRB_WIDTH = "9" *) 
  (* C_ALGORITHM = "1" *) 
  (* C_AXI_ID_WIDTH = "4" *) 
  (* C_AXI_SLAVE_TYPE = "0" *) 
  (* C_AXI_TYPE = "1" *) 
  (* C_BYTE_SIZE = "9" *) 
  (* C_COMMON_CLK = "1" *) 
  (* C_COUNT_18K_BRAM = "0" *) 
  (* C_COUNT_36K_BRAM = "1" *) 
  (* C_CTRL_ECC_ALGO = "NONE" *) 
  (* C_DEFAULT_DATA = "0" *) 
  (* C_DISABLE_WARN_BHV_COLL = "0" *) 
  (* C_DISABLE_WARN_BHV_RANGE = "0" *) 
  (* C_ELABORATION_DIR = "./" *) 
  (* C_ENABLE_32BIT_ADDRESS = "0" *) 
  (* C_EN_DEEPSLEEP_PIN = "0" *) 
  (* C_EN_ECC_PIPE = "0" *) 
  (* C_EN_RDADDRA_CHG = "0" *) 
  (* C_EN_RDADDRB_CHG = "0" *) 
  (* C_EN_SAFETY_CKT = "0" *) 
  (* C_EN_SHUTDOWN_PIN = "0" *) 
  (* C_EN_SLEEP_PIN = "0" *) 
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     5.244 mW" *) 
  (* C_FAMILY = "artix7" *) 
  (* C_HAS_AXI_ID = "0" *) 
  (* C_HAS_ENA = "0" *) 
  (* C_HAS_ENB = "1" *) 
  (* C_HAS_INJECTERR = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_B = "1" *) 
  (* C_HAS_MUX_OUTPUT_REGS_A = "0" *) 
  (* C_HAS_MUX_OUTPUT_REGS_B = "0" *) 
  (* C_HAS_REGCEA = "0" *) 
  (* C_HAS_REGCEB = "0" *) 
  (* C_HAS_RSTA = "0" *) 
  (* C_HAS_RSTB = "0" *) 
  (* C_HAS_SOFTECC_INPUT_REGS_A = "0" *) 
  (* C_HAS_SOFTECC_OUTPUT_REGS_B = "0" *) 
  (* C_INITA_VAL = "0" *) 
  (* C_INITB_VAL = "0" *) 
  (* C_INIT_FILE = "rot_lut.mem" *) 
  (* C_INIT_FILE_NAME = "rot_lut.mif" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "1" *) 
  (* C_MEM_TYPE = "4" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "512" *) 
  (* C_READ_DEPTH_B = "512" *) 
  (* C_READ_LATENCY_A = "1" *) 
  (* C_READ_LATENCY_B = "1" *) 
  (* C_READ_WIDTH_A = "32" *) 
  (* C_READ_WIDTH_B = "32" *) 
  (* C_RSTRAM_A = "0" *) 
  (* C_RSTRAM_B = "0" *) 
  (* C_RST_PRIORITY_A = "CE" *) 
  (* C_RST_PRIORITY_B = "CE" *) 
  (* C_SIM_COLLISION_CHECK = "ALL" *) 
  (* C_USE_BRAM_BLOCK = "0" *) 
  (* C_USE_BYTE_WEA = "0" *) 
  (* C_USE_BYTE_WEB = "0" *) 
  (* C_USE_DEFAULT_DATA = "0" *) 
  (* C_USE_ECC = "0" *) 
  (* C_USE_SOFTECC = "0" *) 
  (* C_USE_URAM = "0" *) 
  (* C_WEA_WIDTH = "1" *) 
  (* C_WEB_WIDTH = "1" *) 
  (* C_WRITE_DEPTH_A = "512" *) 
  (* C_WRITE_DEPTH_B = "512" *) 
  (* C_WRITE_MODE_A = "WRITE_FIRST" *) 
  (* C_WRITE_MODE_B = "WRITE_FIRST" *) 
  (* C_WRITE_WIDTH_A = "32" *) 
  (* C_WRITE_WIDTH_B = "32" *) 
  (* C_XDEVICEFAMILY = "artix7" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  rot_lut_blk_mem_gen_v8_4_9 U0
       (.addra(addra),
        .addrb(addrb),
        .clka(clka),
        .clkb(1'b0),
        .dbiterr(NLW_U0_dbiterr_UNCONNECTED),
        .deepsleep(1'b0),
        .dina({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .dinb({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .douta(douta),
        .doutb(doutb),
        .eccpipece(1'b0),
        .ena(1'b0),
        .enb(enb),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[8:0]),
        .regcea(1'b1),
        .regceb(1'b1),
        .rsta(1'b0),
        .rsta_busy(NLW_U0_rsta_busy_UNCONNECTED),
        .rstb(1'b0),
        .rstb_busy(NLW_U0_rstb_busy_UNCONNECTED),
        .s_aclk(1'b0),
        .s_aresetn(1'b0),
        .s_axi_araddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arburst({1'b0,1'b0}),
        .s_axi_arid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_arready(NLW_U0_s_axi_arready_UNCONNECTED),
        .s_axi_arsize({1'b0,1'b0,1'b0}),
        .s_axi_arvalid(1'b0),
        .s_axi_awaddr({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awburst({1'b0,1'b0}),
        .s_axi_awid({1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awlen({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_awready(NLW_U0_s_axi_awready_UNCONNECTED),
        .s_axi_awsize({1'b0,1'b0,1'b0}),
        .s_axi_awvalid(1'b0),
        .s_axi_bid(NLW_U0_s_axi_bid_UNCONNECTED[3:0]),
        .s_axi_bready(1'b0),
        .s_axi_bresp(NLW_U0_s_axi_bresp_UNCONNECTED[1:0]),
        .s_axi_bvalid(NLW_U0_s_axi_bvalid_UNCONNECTED),
        .s_axi_dbiterr(NLW_U0_s_axi_dbiterr_UNCONNECTED),
        .s_axi_injectdbiterr(1'b0),
        .s_axi_injectsbiterr(1'b0),
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[8:0]),
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[31:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wlast(1'b0),
        .s_axi_wready(NLW_U0_s_axi_wready_UNCONNECTED),
        .s_axi_wstrb(1'b0),
        .s_axi_wvalid(1'b0),
        .sbiterr(NLW_U0_sbiterr_UNCONNECTED),
        .shutdown(1'b0),
        .sleep(1'b0),
        .wea(1'b0),
        .web(1'b0));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2024.2"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
FPXllyX2NFs/RMngGqZy2bLYbZr92CdofeZrJOHklWXExpaPgHNYp2Lzm4MnflbnrfSkCmLwwKT5
zfRgEip7FKQ5Zhb73p0MAIADixBZ/ZRt4hQkJL0T9brm0waLHfanjnov2aCX6jN3LbQc3ujmDga6
Dd73k78u4xjRTDv1/P4=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
kr7VKKvChFoiyRCReag+OvU3jnmG9pN0cv+BxhNmMKLthg/ksgNZyU3L+fQ7cmIQELtlUjwjkBAP
Jjq5RsCnHbJxj+Ys1GNhriiBsxLqxWCP8onhAVvgZN2xZFOih0UWpqlU8NVP8Eww1ohvkDgxTstC
3kDmYehxIUJjqCC/mgRZmuezqugrFdubYmBoz16tUvD17iA5qqCIMS9xSIXYp2LBNekmWEwrVqzu
R4koEo4UlXl/CEw0XY3QvMoHnlXgu6N/6sc+nxZtKSwjiMVvGnZE9UVvJPAC3Hn3zKFGlK53mmGO
Tj0dWzhwX0ahSYzkyJC/HLdbGZmriL2UNvDyFw==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
CaLc9FGt3AdRHfNtGAsGFY/QEvHY1Vv4TvvgCDsdDMqiuDeLizFJDJeskBWjeKDoE2cufK8TxiBq
mySRQNJoeOKnxTiDdf+Rx6m0iR6h/YeswegYwgghpM5KVrl6mSwF3+4yEovPM7a+9ArDQ5vl+WT8
SilNGzyW0KnTwe7+szs=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
cEnudSW1X71p0Xuq6jrXOxHnBku87IA0RA3zKqmeZHZM0r+9rEm5MSzX8RecnQ994yiqeyxbIH2l
fGEzUzr0ZzryS3fkf2LnJuB39f2YARW9eVCSiaeWaraZuY1l89T+h3vgdlurS/1LIraYLS1MyOXa
6F1LAcQp3W4OO4ctc3q1FRMZGldRS1biMsKwJ8Lxj8NEOm67UfgFrJNQAxbVXEfbWRWhKtwNxcTB
JbgC8j4EHkIA46mzoHloeBAL6KieplQUBjKXSSTb66rxglbFhWLy+mirROHcocu9J4ZbvTRYZEww
4lso1lqAllVLAoKYqa3WImZuSRoTbGDngBt9Lg==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
rOyI+x4PlmKcVSFoN3oKgSYpVlmYxc194Ej04il/YmBg10xopy4zmtu5sdCP/uGSNYcNGWeAiw01
mNf98KyNgTUFXruHCA38qjhhEIvl4vfWWn3W3mFRxrIuwmnreT6qTvgMaxIkCdVBDP7Iy7O6WmCf
3Va5X5hnCHhtXgX5UYniBHiLjmupv63B8XMAYDH2n6mQ3H0DF7mtb7psBafd0Z6+IWUbmzwMtKrf
ZrRJBGAhNT0i1KrEjEh/rWjN7Z7N32zQ+Pl1kc5gYCQIX5McfdTdqSaRVXZ/HF90ymS7/8d5LDyj
Er+ORdcjnOn6oAyY4PuUUl4OYUHv5k+RglTe5Q==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2023_11", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
bJa7kPSpDipzoJoQu1APEjc8vFLqBfQZK/grZvWijD7/FgMTerFCWLUY6n8DWeGdvjXvTeyrqCHE
2rP/H57wUqPC8tIJlGm6ZYQGjZ3TgYqLrJshDE5zYMTO//q0vuSraWvZP7A7SLuW6y7tFE/nplpx
L8gbYORx6j70okGUwnamCMS9yhFr7Z2QTJne1k4GNFGvy66URk3k5cBPl5j4/1yc4xGV+aWYl6L8
q8RorRU/CltObHKrji/jdiY1WtdGrkpRyCEFc+XNPazL9xSLLu5bz6XlvKwoks+8a5KYT/VFUovM
JbM0bpAXM8Z7rGaPuXjqXtZBg5praTZLu/WNcA==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
PYKBDinOGc/kIVdFzXrz2wA4/QNFxLDrQfTWfR5TjYE6bm49vrZi0bawcr9HXp4OP1+XxPLB3oCP
oV5e/rYeDln531ebt8yEg27XCoSHEX4FU8oG8aBJ8fqgWayOnAMJt025WodOxuZXbhT1zPo7J3uh
6iO9Mv7RtYE2fZ1W+G8oN//FTOEJYPWlKYnt0cDeZrN3I4rHHptZHuu7l8T+df0PYea3x6U3Mvkl
ojZ+TwQtdu0NuYY5j3QNgx3+W2XYq1M773FAnEz/deW54EjE+jf1jjrBk2pl8SYxeKuutS15oPVF
eHdqXYVcJxoUY5JH8z04lITKEnZ4oq6sYS6dog==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
tl+2vFCWZ583gQGsVC7oopz2NCKBiJ9uOHYBGzJZheOHJMqI/ehNvo25l710eBx00tztXzM30AH6
ZhAJg+kJwE2jO0MV5fmG5dnwXmLqoGEJMBs7xwWxvYK7w/0z9M0AJKD7HnuC+IiLhNU/fIxyuE+I
+vWqp//RcfY0tMMp2I2J1yEW6GUahS1ve/4JchssZ7Xu7VthoSDWXMQWATbvsUsDzeSo2+Ruz8Kq
Dc05HqEU8NgBxDPPEKLCcdKLp4byglwj7iCAtCjsPy8P18qjgb2sycFjNgmaiNMMB51WqeD+hneG
hLOue9bqVdEojkrb3q4WbsGZKz0bAGsryxslOlYHP1b8vey3yI2ixA80wyERe8d3GRIeZiSxGykH
qWxsE6x/iyi8QRb5mXZPMApA+Fln8tYmn7+1rFCm8gF4gJWhr1PsSJqTi658symGrzT0Ghjvf2QL
SvvoaeNdy0pOsWs7jLBFndd4GiFA+9K6Y33sziLToU9EvvFokENIslod

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
oYiCujFRj1F3wKsGZlHR9niEtR9MLXEVAVfy+f/3xrmpW6Ye5a+fBCvm4TH+iRQefGHNdMPnzTNW
K/pEPAS9uMJjOdFiu+APT+LYrSRnEg4W0dX5buSDGM6LBWAuMseoTMjbJJoYDGLRckJgW43E30mX
ej4823nkbfwc+Ecbrup825qLyv8RTQLNHafvJA5lSapdqXwnlOIYRmcHn+sfAh5pGv9kW9aokcdh
ObR2XYxX99rYloyvz3x0pmjxD5ILW4SQMB1IUEuuyqX6eb5IQ+kZ41hjvsHIuQH29vzpCfV9Jqha
WC5yxxK1R+cleZSKD1H1gVzbTei8uFs/91Bgeg==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
urNc+S8AFPj+GVFdqJE5V7P8O6QI6MA3nkwYb8NKbYbVufnXKg6voJIRYYeYr7EOa8mrqirozWbY
Lln9SLWnkaAy2LvL/N6WahoQdCt++4RH+xe768XvSrVUFPrIwZRixqMLurc/tPov4i5P/ukZKl18
ZPZvXRzUNlvCZnMPcF+5QCQihqPbjcZ0YyGgWgX/ipTGG3sNqmylGN7qLa4Rgqu/mB5a2xVyu5Wc
911+/X3VVFx697WVaP5V0SbOzYN8R8+8B8kdznwixMA+f4lSbBXyRysVOSzYjo8bKEMqyKMVBQn9
xDmEuV0DvVWXdO7VPvWA1LuJFwS07OxeI2GCcQ==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
QcP7fsLZxaDrG29e9HQeXfu2TsKsdyW7Yc1vWct6lbmDEfXkWMU1fFWSPIjPzRc9UOnfEu0bRn+B
D+8MWokqes3WF7txljBmgUPiNGZ8arUU6ENa/IY/Wv7iaB/ZKM5PtdnFAkjDIrYyKFCTz/U6Yzwi
hBGGarK/wYQOLzeeKRewiPTiNUL7tztWuMZ1t1msxD951EeKrwjrjcXIIuf/TzrOGUOlWgjHlnrl
4Q/lfMAnRLBNTSWG+5wWewCE8jK2X/gJ5AV4p3x1WP3+JglbxpP39l3pzedXqciZPbuz2XlFnRPV
KByaUaAShzJ56p8+0HjWebibqQdieGNPiPWW0Q==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 27248)
`pragma protect data_block
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
en4=
`pragma protect end_protected
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
