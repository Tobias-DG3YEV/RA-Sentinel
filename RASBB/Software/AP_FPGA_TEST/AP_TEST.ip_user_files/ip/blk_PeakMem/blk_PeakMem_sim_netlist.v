// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.1.1 (win64) Build 5094488 Fri Jun 14 08:59:21 MDT 2024
// Date        : Wed Jun 26 10:03:25 2024
// Host        : hpelite running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               C:/Data/RASentinel/RASM2400/RASM2400.runs/blk_PeakMem_synth_1/blk_PeakMem_sim_netlist.v
// Design      : blk_PeakMem
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7a100tfgg676-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "blk_PeakMem,blk_mem_gen_v8_4_8,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_8,Vivado 2024.1" *) 
(* NotValidForBitStream *)
module blk_PeakMem
   (clka,
    ena,
    wea,
    addra,
    dina,
    douta,
    clkb,
    web,
    addrb,
    dinb,
    doutb);
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTA, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clka;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA EN" *) input ena;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA WE" *) input [0:0]wea;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA ADDR" *) input [9:0]addra;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DIN" *) input [7:0]dina;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTA DOUT" *) output [7:0]douta;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME BRAM_PORTB, MEM_ADDRESS_MODE BYTE_ADDRESS, MEM_SIZE 8192, MEM_WIDTH 32, MEM_ECC NONE, MASTER_TYPE OTHER, READ_LATENCY 1" *) input clkb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB WE" *) input [0:0]web;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB ADDR" *) input [9:0]addrb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DIN" *) input [7:0]dinb;
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB DOUT" *) output [7:0]doutb;

  wire [9:0]addra;
  wire [9:0]addrb;
  wire clka;
  wire clkb;
  wire [7:0]dina;
  wire [7:0]dinb;
  wire [7:0]douta;
  wire [7:0]doutb;
  wire ena;
  wire [0:0]wea;
  wire [0:0]web;
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
  wire [9:0]NLW_U0_rdaddrecc_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_bid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_bresp_UNCONNECTED;
  wire [9:0]NLW_U0_s_axi_rdaddrecc_UNCONNECTED;
  wire [7:0]NLW_U0_s_axi_rdata_UNCONNECTED;
  wire [3:0]NLW_U0_s_axi_rid_UNCONNECTED;
  wire [1:0]NLW_U0_s_axi_rresp_UNCONNECTED;

  (* C_ADDRA_WIDTH = "10" *) 
  (* C_ADDRB_WIDTH = "10" *) 
  (* C_ALGORITHM = "1" *) 
  (* C_AXI_ID_WIDTH = "4" *) 
  (* C_AXI_SLAVE_TYPE = "0" *) 
  (* C_AXI_TYPE = "1" *) 
  (* C_BYTE_SIZE = "9" *) 
  (* C_COMMON_CLK = "0" *) 
  (* C_COUNT_18K_BRAM = "1" *) 
  (* C_COUNT_36K_BRAM = "0" *) 
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
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     2.8113 mW" *) 
  (* C_FAMILY = "artix7" *) 
  (* C_HAS_AXI_ID = "0" *) 
  (* C_HAS_ENA = "1" *) 
  (* C_HAS_ENB = "0" *) 
  (* C_HAS_INJECTERR = "0" *) 
  (* C_HAS_MEM_OUTPUT_REGS_A = "1" *) 
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
  (* C_INIT_FILE = "blk_PeakMem.mem" *) 
  (* C_INIT_FILE_NAME = "no_coe_file_loaded" *) 
  (* C_INTERFACE_TYPE = "0" *) 
  (* C_LOAD_INIT_FILE = "0" *) 
  (* C_MEM_TYPE = "2" *) 
  (* C_MUX_PIPELINE_STAGES = "0" *) 
  (* C_PRIM_TYPE = "1" *) 
  (* C_READ_DEPTH_A = "1024" *) 
  (* C_READ_DEPTH_B = "1024" *) 
  (* C_READ_LATENCY_A = "1" *) 
  (* C_READ_LATENCY_B = "1" *) 
  (* C_READ_WIDTH_A = "8" *) 
  (* C_READ_WIDTH_B = "8" *) 
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
  (* C_WRITE_DEPTH_A = "1024" *) 
  (* C_WRITE_DEPTH_B = "1024" *) 
  (* C_WRITE_MODE_A = "READ_FIRST" *) 
  (* C_WRITE_MODE_B = "READ_FIRST" *) 
  (* C_WRITE_WIDTH_A = "8" *) 
  (* C_WRITE_WIDTH_B = "8" *) 
  (* C_XDEVICEFAMILY = "artix7" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  blk_PeakMem_blk_mem_gen_v8_4_8 U0
       (.addra(addra),
        .addrb(addrb),
        .clka(clka),
        .clkb(clkb),
        .dbiterr(NLW_U0_dbiterr_UNCONNECTED),
        .deepsleep(1'b0),
        .dina(dina),
        .dinb(dinb),
        .douta(douta),
        .doutb(doutb),
        .eccpipece(1'b0),
        .ena(ena),
        .enb(1'b0),
        .injectdbiterr(1'b0),
        .injectsbiterr(1'b0),
        .rdaddrecc(NLW_U0_rdaddrecc_UNCONNECTED[9:0]),
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
        .s_axi_rdaddrecc(NLW_U0_s_axi_rdaddrecc_UNCONNECTED[9:0]),
        .s_axi_rdata(NLW_U0_s_axi_rdata_UNCONNECTED[7:0]),
        .s_axi_rid(NLW_U0_s_axi_rid_UNCONNECTED[3:0]),
        .s_axi_rlast(NLW_U0_s_axi_rlast_UNCONNECTED),
        .s_axi_rready(1'b0),
        .s_axi_rresp(NLW_U0_s_axi_rresp_UNCONNECTED[1:0]),
        .s_axi_rvalid(NLW_U0_s_axi_rvalid_UNCONNECTED),
        .s_axi_sbiterr(NLW_U0_s_axi_sbiterr_UNCONNECTED),
        .s_axi_wdata({1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0}),
        .s_axi_wlast(1'b0),
        .s_axi_wready(NLW_U0_s_axi_wready_UNCONNECTED),
        .s_axi_wstrb(1'b0),
        .s_axi_wvalid(1'b0),
        .sbiterr(NLW_U0_sbiterr_UNCONNECTED),
        .shutdown(1'b0),
        .sleep(1'b0),
        .wea(wea),
        .web(web));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2024.1"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
RSqbsRZSIb+QlYJMfFv1T7uHQ7PiCEXQkl687MHGm2LgPB15GIYcPmqKUSXgtkLsIFes91PTAyyB
9H9cyY4ZUxedcRg/9ZOB5pm3zPqAbcvGPmg1ivMhr/MlS19t5lYKM2tQo+0Yd+arJXlVZu2BMnvn
+I3G9t9tJuWUIWKjI+I=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
VRSQ05ZaB6bIhFIQ823mTvlJaG9+5iW5C3+KxGjq0sq9ziCshKOLpOGPDMmOWDqA4uBaxC5IKISr
w8+A8mqbYjXo5m1g8sGjNaETS0HKJsK+l5Y++tN4IEUs+DwxgrPR/+LWtChuOzVkfC7BG3LVUEMj
zM3GAyGcXGJ3sdBItZAfsevyiy7kr4Fw+nk2hWytGteu1NZk3VzPE7KQHLkOlHBPXf6P0j8LpKcr
2oNDgQ/WaEmg6OOvFeJuaWDaee8Sn6wKP/caMyoGdSeczsPtRrJeoSRlbNHlxhCv7zg+Cn2AgwrR
PTqGsMrkhv9U0sq+waS0CmwChsk4WB7RspGYUg==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
tNziOjCznlvIl4dadmB9r23Duf+HQHWOuHmupEU3PJxrazHVtZdNKspG9sRXhF9mjbpnSiKYCdFK
Jr9W/dxUid36faFIPKQazVTuOiE0hkzVQAGpYxXjT/ITB/9EFBvgvP5L3EAhHv32x6MA1vkFSI7x
HrZ09YNFEF6T7DPTZE4=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
QCYfxgkUHlX1cre1q9aS3sVDIOX36YBK4ZwJXAVUwA6f1OQ77XibjpWJHt5FK9F0PcYp/j21pqzO
BRdkDcFLVAjxER4J5t5iMVhoeMk+3fpiKfYrm4WFl1ygsJsfFJP0jqO1OkjC8iFBtm3n6b7CTl1o
cjBbcBp8UgW6E8rf5inXA0dRqybnyxKJSnMFYLinvpVU6QEc4OKO7mi/i/s9p/efiP+CdQf0yDRU
Fw7o7x0D7tjBv943g5L+4wGZ2JYU+ISqn4Ajxy/bWTTJDe6T/15evhngS61MC8Xjamzc4YLZBP8o
ShfSLoeZeO+Hk5n3xzJRghM0DQ6Sj7NqXFY68w==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Uy8FDDy3dZQGAnMQV0HBesEs+/oZdaq35Kj1PGhy9J/+EBZm0nhhQgYtku8tWABW2jKAC1GtNTvo
uReQyr1hteMxTbD5OIuqv86eb1hXZVENlZ7ichG8auUjkeHAkaSYNbHOuDLIhSqHEL67XbcZ9zPG
1JOY3+VONSww0KYPcQbGSo/2DaC5C0Y+mZODRfJ4+b0WXjce6UaJetilBc3VtqqmodIM2d3HDawF
R0xVJfHj86rXmUkY+SNUw60zsV6raCY6G3k/rXpei1d6zn8tCThkKG5fwiWY8zA7kRdTFIlVKP9h
fb6kfzRBRT/BgVQ8d4RgEcEVV8m3u/Mf4KIlTw==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2023_11", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Pk1GeRlkUK9lt6DVXYVdtOABlzDEWQDcBsP/p+Wo5HaglDLG5b8gk08xTP3IcJ1RKcfuARPMGO2s
/VqFbnVADV90T1rhjIuWMcBnzYQK/ALUvwv11Uju9Gn0fvPIz52l3QBnpjHI1nlsFB7WeqkzVfHZ
tg9gO9bPHjHLjVd9BzH6McrEWY5RkZ0UBy0Fmh/SownJX1b0YGE7LdwKydEMEpyvb28bwTOwfEv/
4RtsfYtEvTjo6e1ZBm66D9IQmKUu32wzTfn5bFZHdyjZg6+HcTzvHMtQX2+AggXfP6FsO2/83qkb
0bfj226fnLhr32dJxtsaJS5OR63GYtzDJ05ITA==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
LCfWqKmUoUSVOTKNAl5p8n1hfz7SMU2kDOUMBjsDncgSFqiu2zUy1I6GSDrVnF/2umJG5/mWcpvi
rQaFJOlrJ8DNctSuavdlopRAwTMsVi6dAlNGrAawSiDIxtI3tN3MDVdMiH5H+pJMqMt59yXneyCf
2RRSRz2sUQK/aj0lXlqKjVJzVbk8HaBQ8akBJF4iWSMK4foIzJ6iO1EupYovuW6uEiO7jQRWezlW
pbbDenOHHWbfinuX5cbkjpTKHGsEKct65q+ZXJp60m3sconSK3Y2eLQxusuJ1FHDJ4GGKO8mEzCv
3cfGdXX3pVL81OfGO/JD1aMs9H98CO5ssbHqlw==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
A4S1e3DHcTeWzaDVuWDRb3Yf1BjiEsR1RtAeL0BJ7J/oPWMNj96MeGsUiHtZoiYqteTZxqax2cyZ
PV0cMLoBK4Ya8CyM+BTnkFA2ablsGt5Es4TgG/nFS9VEhmeKxu8boAsqW5697aiqOATJf/LucQh5
GOnPXHAuPrDj0A/fu8N2QduqGyysWUSc1KsoJ0/0noJYvLJ2yOhFi4uIUYQfG5LOuOrca5P43pqA
iwUKW/RrFXal2acJdFeXIKffZpKanSV97urdzKyBvf9EPV/M8g9uPFJJ1z6aS+FbknhVPs0pt6eD
+J/qib4gVp/HGnRo4YlxauUMv6Yv9wxiaObY6ttDfYf5p3uzWZMlf3i7YOzZwcd4aS/6+vkD28LG
L9piBIpLx2dvQy74RdvCVdvaP1LC6RMju9RfuXJhuX4ZAmDxRi0zQyRda838ikzwYeOCSKLIvRPb
nuJ8Zx2ot8EFqSeGaaRFaEMU6Zf5SptCUuVMHvSkinBewcwrLB5uiJTJ

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
gj+uMxV+tK4Di7pgSOE82FOBeWmUB1A7OKFOSMUW3qrmQ4/YhryfHMlWPxfAq8avQL7tnBTnRFEg
czbErdIcNzYjrM7Qq00QC/mTqmeQX4/apbqGvN+rwK4RR5oj22wfTib/UQNEQX6fbpi6PtmAeUR9
eShsfq+YWcf7z2Zw4Q+o4+E6m4/3CzU68vglNpzNsJ8S9/8XpdIrvAA/WRAX6OEOC4wlNIKDZsq/
+zMbFgSzN1rP844I/CDmxYM0NIzBWWhYBkPfJyQyigmUoXb84lDip0/Dmnq4EHvu7D/tZNnDl5st
JpftRfEpT6S8e/5MBeKUuhbfg6etHo/oFZvPKQ==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
aWTy3xv6SqKsldtLS2gY4KrTS8U+KtFNRHS314f6EYZy1MHE9t7oICJ8eNB8up8A+odoE23N3fJb
1alhaadeRWU2GjlIiK1LjZ5PQw+jb1u1GWtRiY+TcTlD75XUlqwykVBrCDfm565DmgZjZle9T3/t
WEfLo+m/8GfBe8trVnoftsk/XI00BMFXRzw8doPGDhNECS1NUrLebryb9iO5Hf4A/40dtslTARsR
nicN0KoIIyiQ+QzliqyXU/8VjS45inON8R0Kv9Qx46EXUp7bds5uQ7QycRhpLG0IPnMIweudU67w
eQmpHJzvZKBCZks/R0OafZx44H6Jib2+QazBCw==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
UGdPiChIPj1lSozqzCQx17Bi+8FWSuMUMzXUkDLH5zcP1t8tZLzh4CU4WAR8lmJxn8gH763fLp5c
RYU6zA0yxHzl2ksc5YRU1XEfQQT9ha8fQnz+18wVKcsa5UIOfMbGDwnS9yfX59ntG8CB0uF8bJKE
y1CS6U/1Stfs1w2mF94iDxI2n2GJlb1UPtWpmxMBI88hY0GktTPXP2Y7JKl8zRl/Lq0wIF8pHwXk
B4nOgKm6hfzPj0xZ6E/TuER/JE3fy8RSm24IlL/CUgpReEslEOYjQ4EKKZRG9/fxg26utQWW9p+G
fWVU53qrFGzBhKQ96Paj1ROkv6hDHyUb6n7uSw==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 21824)
`pragma protect data_block
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
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
