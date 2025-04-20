############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
#############SPI Configurate Setting ##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
set_property CONFIG_MODE SPIx1 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
############## clock and reset define##################
#create_generated_clock -name adc_process_clk -source [get_pins lvds_irx0/CLK] -divide_by 2 [get_pins fft0/adc_processClock_BUFG]

set_property IOSTANDARD LVCMOS33 [get_ports SYS_clk]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_idataH_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_qdataH_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_frame_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_idataL_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_qdataL_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_bitclk_P]

#set_property IODELAY_GROUP DDR_GROUP [get_cells idelay_Q0]
#set_property IODELAY_GROUP "DDR_GROUP" [get_ports {ADC_frame_P}]
#set_property IODELAY_GROUP "DDR_GROUP" [get_clocks {clk_ref}]
############## HDMIOUT define##################
#set_property IOSTANDARD DIFF_SSTL18_I [get_ports TMDS_clk_n]
#set_property PACKAGE_PIN D4 [get_ports TMDS_clk_p]
#set_property PACKAGE_PIN C4 [get_ports TMDS_clk_n]
#set_property IOSTANDARD DIFF_SSTL18_I [get_ports TMDS_clk_p]

#set_property IOSTANDARD DIFF_SSTL18_I [get_ports {TMDS_data_n[0]}]
#set_property PACKAGE_PIN E1 [get_ports {TMDS_data_p[0]}]
#set_property PACKAGE_PIN D1 [get_ports {TMDS_data_n[0]}]
#set_property IOSTANDARD DIFF_SSTL18_I [get_ports {TMDS_data_p[0]}]

#set_property IOSTANDARD DIFF_SSTL18_I [get_ports {TMDS_data_n[1]}]
#set_property PACKAGE_PIN F2 [get_ports {TMDS_data_p[1]}]
#set_property PACKAGE_PIN E2 [get_ports {TMDS_data_n[1]}]
#set_property IOSTANDARD DIFF_SSTL18_I [get_ports {TMDS_data_p[1]}]

#set_property IOSTANDARD DIFF_SSTL18_I [get_ports {TMDS_data_n[2]}]
#set_property PACKAGE_PIN G2 [get_ports {TMDS_data_p[2]}]
#set_property PACKAGE_PIN G1 [get_ports {TMDS_data_n[2]}]
#set_property IOSTANDARD DIFF_SSTL18_I [get_ports {TMDS_data_p[2]}]

############## SPI PORT ###################


################ CLOCKS ####################
create_clock -period 16.666 -name ADC_bitclk_P -waveform {0.000 8.333} -add [get_ports ADC_bitclk_P]
create_clock -period 50.000 -name ADC_frame_P -waveform {4.166 29.166} -add [get_ports ADC_frame_P]


set_input_delay -clock [get_clocks ADC_bitclk_P] 2.000 [get_ports ADC_idataL_P]
set_input_delay -clock [get_clocks ADC_bitclk_P] 2.000 [get_ports ADC_idataH_P]
set_input_delay -clock [get_clocks ADC_bitclk_P] 2.000 [get_ports ADC_qdataL_P]
set_input_delay -clock [get_clocks ADC_bitclk_P] 2.000 [get_ports ADC_qdataH_P]
set_input_delay -clock [get_clocks ADC_bitclk_P] 4.000 [get_ports ADC_frame_P]






set_clock_groups -asynchronous -group [get_clocks [list ADC_bitclk_P [get_clocks -of_objects [get_pins clk_system_inst/inst/mmcm_adv_inst/CLKOUT3]]]]

#set_false_path -from [get_pins dot11_inst/pkt_header_valid_reg/C]


set_property PACKAGE_PIN J3 [get_ports ADC_bitclk_P]
set_property PACKAGE_PIN E3 [get_ports SYS_clk]
set_property PACKAGE_PIN C2 [get_ports ADC_frame_P]
set_property PACKAGE_PIN G4 [get_ports ADC_idataL_P]
set_property PACKAGE_PIN H2 [get_ports ADC_idataH_P]
set_property PACKAGE_PIN E6 [get_ports ADC_qdataH_P]
set_property PACKAGE_PIN F4 [get_ports ADC_qdataL_P]



set_property PACKAGE_PIN V10 [get_ports {dbgOutI[0]}]
set_property PACKAGE_PIN V11 [get_ports {dbgOutI[1]}]
set_property PACKAGE_PIN U11 [get_ports {dbgOutI[2]}]
set_property PACKAGE_PIN V12 [get_ports {dbgOutI[3]}]
set_property PACKAGE_PIN U12 [get_ports {dbgOutI[4]}]
set_property PACKAGE_PIN U13 [get_ports {dbgOutI[5]}]
set_property PACKAGE_PIN V14 [get_ports {dbgOutI[6]}]
set_property PACKAGE_PIN V15 [get_ports {dbgOutI[7]}]
set_property PACKAGE_PIN V16 [get_ports {dbgOutI[8]}]
set_property PACKAGE_PIN U16 [get_ports {dbgOutI[9]}]
set_property PACKAGE_PIN V17 [get_ports {dbgOutI[10]}]
set_property PACKAGE_PIN T14 [get_ports {Jumpers[5]}]
set_property PACKAGE_PIN R13 [get_ports {Jumpers[4]}]
set_property PACKAGE_PIN T13 [get_ports {Jumpers[3]}]
set_property PACKAGE_PIN R12 [get_ports {Jumpers[2]}]
set_property PACKAGE_PIN T11 [get_ports {Jumpers[1]}]
set_property PACKAGE_PIN T10 [get_ports {Jumpers[0]}]
set_property PACKAGE_PIN B18 [get_ports {TMDS_data_p[2]}]
set_property PACKAGE_PIN A15 [get_ports {TMDS_data_p[1]}]
set_property PACKAGE_PIN B16 [get_ports {TMDS_data_p[0]}]
set_property PACKAGE_PIN P14 [get_ports dbgBitClk]
set_property PACKAGE_PIN T15 [get_ports dbgFrameRdy]
set_property IOSTANDARD LVCMOS18 [get_ports dbgBitClk]
set_property IOSTANDARD LVCMOS18 [get_ports dbgFrameRdy]
set_property PACKAGE_PIN A13 [get_ports TMDS_clk_p]

set_property PACKAGE_PIN U17 [get_ports {dbgOutI[11]}]
set_property PACKAGE_PIN U18 [get_ports {dbgOutQ[0]}]
set_property PACKAGE_PIN R17 [get_ports {dbgOutQ[2]}]
set_property PACKAGE_PIN T18 [get_ports {dbgOutQ[1]}]
set_property PACKAGE_PIN R18 [get_ports {dbgOutQ[3]}]
set_property PACKAGE_PIN M14 [get_ports {dbgOutQ[11]}]
set_property PACKAGE_PIN N14 [get_ports {dbgOutQ[10]}]
set_property PACKAGE_PIN P17 [get_ports {dbgOutQ[9]}]
set_property PACKAGE_PIN P18 [get_ports {dbgOutQ[8]}]
set_property PACKAGE_PIN N17 [get_ports {dbgOutQ[7]}]
set_property PACKAGE_PIN M17 [get_ports {dbgOutQ[6]}]
set_property PACKAGE_PIN M18 [get_ports {dbgOutQ[5]}]
set_property PACKAGE_PIN L18 [get_ports {dbgOutQ[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutI[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[10]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[9]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[8]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[7]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[6]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgOutQ[0]}]
set_property IOSTANDARD LVCMOS18 [get_ports {Jumpers[5]}]
set_property IOSTANDARD LVCMOS18 [get_ports {Jumpers[4]}]
set_property IOSTANDARD LVCMOS18 [get_ports {Jumpers[3]}]
set_property IOSTANDARD LVCMOS18 [get_ports {Jumpers[2]}]
set_property IOSTANDARD LVCMOS18 [get_ports {Jumpers[1]}]
set_property IOSTANDARD LVCMOS18 [get_ports {Jumpers[0]}]
