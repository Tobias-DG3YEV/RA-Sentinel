// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2024 Advanced Micro Devices, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2024.1 (win64) Build 5076996 Wed May 22 18:37:14 MDT 2024
// Date        : Sun Jun  2 14:39:06 2024
// Host        : PC1008 running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim -rename_top blk_mem_gen_0 -prefix
//               blk_mem_gen_0_ blk_mem_gen_0_sim_netlist.v
// Design      : blk_mem_gen_0
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xc7a100tfgg676-1
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "blk_mem_gen_0,blk_mem_gen_v8_4_8,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "blk_mem_gen_v8_4_8,Vivado 2024.1" *) 
(* NotValidForBitStream *)
module blk_mem_gen_0
   (clka,
    ena,
    wea,
    addra,
    dina,
    douta,
    clkb,
    enb,
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
  (* x_interface_info = "xilinx.com:interface:bram:1.0 BRAM_PORTB EN" *) input enb;
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
  wire enb;
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
  (* C_EST_POWER_SUMMARY = "Estimated Power for IP     :     2.7573 mW" *) 
  (* C_FAMILY = "artix7" *) 
  (* C_HAS_AXI_ID = "0" *) 
  (* C_HAS_ENA = "1" *) 
  (* C_HAS_ENB = "1" *) 
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
  (* C_INIT_FILE = "blk_mem_gen_0.mem" *) 
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
  (* C_WRITE_MODE_B = "WRITE_FIRST" *) 
  (* C_WRITE_WIDTH_A = "8" *) 
  (* C_WRITE_WIDTH_B = "8" *) 
  (* C_XDEVICEFAMILY = "artix7" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  blk_mem_gen_0_blk_mem_gen_v8_4_8 U0
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
        .enb(enb),
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
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 21840)
`pragma protect data_block
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
5RUynZiReKKr
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
