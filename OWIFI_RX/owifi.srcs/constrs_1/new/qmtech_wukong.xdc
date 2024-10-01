############## NET - IOSTANDARD ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
#############SPI Configurate Setting ##################
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]
############## clock and reset define##################
#create_generated_clock -name adc_process_clk -source [get_pins lvds_irx0/CLK] -divide_by 2 [get_pins fft0/adc_processClock_BUFG]

set_property IOSTANDARD LVCMOS33 [get_ports SYS_clk]
set_property PACKAGE_PIN M21 [get_ports SYS_clk]
set_property PACKAGE_PIN B5 [get_ports ADC_bitclk_P]
set_property PACKAGE_PIN A5 [get_ports ADC_bitclk_N]
set_property PACKAGE_PIN B4 [get_ports ADC_frame_P]
set_property PACKAGE_PIN A4 [get_ports ADC_frame_N]
set_property PACKAGE_PIN E6 [get_ports ADC_idataL_P]
set_property PACKAGE_PIN D6 [get_ports ADC_idataL_N]
set_property PACKAGE_PIN G4 [get_ports ADC_qdataL_P]
set_property PACKAGE_PIN F4 [get_ports ADC_qdataL_N]
set_property PACKAGE_PIN E5 [get_ports ADC_idataH_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_idataH_P]
set_property PACKAGE_PIN J4 [get_ports ADC_qdataH_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_qdataH_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_frame_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_idataL_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_qdataL_P]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_bitclk_P]
set_property PACKAGE_PIN H7 [get_ports Key0]
set_property PACKAGE_PIN M6 [get_ports Key1]
set_property IOSTANDARD LVCMOS18 [get_ports Key0]
set_property IOSTANDARD LVCMOS18 [get_ports Key1]
set_disable_timing [get_ports Key0]
set_disable_timing [get_ports Key1]

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
set_property PACKAGE_PIN T19 [get_ports SPI_clk]
set_property PACKAGE_PIN U19 [get_ports SPI_miso]
set_property PACKAGE_PIN U20 [get_ports SPI_mosi]


################ CLOCKS ####################
create_clock -period 16.666 -name ADC_bitclk_P -waveform {0.000 8.333} -add [get_ports ADC_bitclk_P]
create_clock -period 50.000 -name ADC_frame_P -waveform {4.166 29.166} -add [get_ports ADC_frame_P]
create_generated_clock -name fclk_delayed -source [get_pins lvds_irx0/fclk_delayed_reg/C] -multiply_by 1 -add -master_clock ADC_bitclk_P [get_pins lvds_irx0/fclk_delayed_reg/Q]

create_clock -period 20.000 -name SPI_Clock -waveform {0.000 10.000} -add [get_ports SPI_clk]
set_input_delay -clock [get_clocks SPI_Clock] -add_delay 5.000 [get_ports SPI_clk]
set_clock_groups -name SPI_SYS_clk -asynchronous -group [get_clocks {SPI_Clock SYS_clk}]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets SPI_clk_IBUF]

set_input_delay -clock [get_clocks ADC_bitclk_P] 2.000 [get_ports ADC_idataL_P]
set_input_delay -clock [get_clocks ADC_bitclk_P] 2.000 [get_ports ADC_idataH_P]
set_input_delay -clock [get_clocks ADC_bitclk_P] 2.000 [get_ports ADC_qdataL_P]
set_input_delay -clock [get_clocks ADC_bitclk_P] 2.000 [get_ports ADC_qdataH_P]
set_input_delay -clock [get_clocks ADC_bitclk_P] 4.000 [get_ports ADC_frame_P]

set_property IOSTANDARD LVCMOS33 [get_ports SPI_clk]
set_property IOSTANDARD LVCMOS33 [get_ports SPI_miso]
set_property IOSTANDARD LVCMOS33 [get_ports SPI_mosi]
set_property IOSTANDARD LVCMOS33 [get_ports SPI_nss]

set_property IOSTANDARD LVCMOS33 [get_ports {o_byteOut[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_byteOut[6]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_byteOut[5]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_byteOut[4]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_byteOut[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_byteOut[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_byteOut[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_byteOut[0]}]

set_property PACKAGE_PIN AB26 [get_ports {o_byteOut[0]}]
set_property PACKAGE_PIN AC26 [get_ports {o_byteOut[1]}]
set_property PACKAGE_PIN AB24 [get_ports {o_byteOut[2]}]
set_property PACKAGE_PIN AC24 [get_ports {o_byteOut[3]}]
set_property PACKAGE_PIN AA24 [get_ports {o_byteOut[4]}]
set_property PACKAGE_PIN AB25 [get_ports {o_byteOut[5]}]
set_property PACKAGE_PIN AA22 [get_ports {o_byteOut[6]}]
set_property PACKAGE_PIN AA23 [get_ports {o_byteOut[7]}]
set_property PACKAGE_PIN Y25 [get_ports o_byteOutStrobe]
set_property IOSTANDARD LVCMOS33 [get_ports o_byteOutStrobe]
set_property DRIVE 12 [get_ports SPI_miso]
set_property PACKAGE_PIN W21 [get_ports sig_valid]
set_property IOSTANDARD LVCMOS33 [get_ports sig_valid]
set_property DRIVE 12 [get_ports sig_valid]

set_property MARK_DEBUG true [get_nets receiver_rst]
set_property MARK_DEBUG true [get_nets o_state]

set_property PACKAGE_PIN W25 [get_ports {o_state[0]}]
set_property PACKAGE_PIN Y26 [get_ports {o_state[1]}]
set_property PACKAGE_PIN Y22 [get_ports {o_state[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_state[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_state[2]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_state[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {o_state[0]}]
set_property PACKAGE_PIN Y23 [get_ports {o_state[3]}]
set_property PACKAGE_PIN Y21 [get_ports o_short_sync]
set_property IOSTANDARD LVCMOS33 [get_ports o_short_sync]


set_clock_groups -asynchronous -group [get_clocks [list ADC_bitclk_P [get_clocks -of_objects [get_pins clk_system_inst/inst/mmcm_adv_inst/CLKOUT3]]]]
set_false_path -from [get_clocks ADC_bitclk_P] -to [get_clocks -of_objects [get_pins clk_system_inst/inst/mmcm_adv_inst/CLKOUT3]]

set_false_path -from [get_pins {signal_watchdog_inst/small_abs_eq_i_counter_reg[4]/C}]
set_false_path -from [get_pins {signal_watchdog_inst/small_abs_eq_i_counter_reg[5]/C}]
set_false_path -from [get_pins {signal_watchdog_inst/small_abs_eq_q_counter_reg[5]/C}]
set_false_path -from [get_pins {signal_watchdog_inst/small_abs_eq_q_counter_reg[3]/C}]
set_false_path -from [get_pins {signal_watchdog_inst/small_abs_eq_i_counter_reg[3]/C}]
set_false_path -from [get_pins {signal_watchdog_inst/small_abs_eq_q_counter_reg[4]/C}]
#set_false_path -from [get_pins dot11_inst/pkt_header_valid_reg/C]
set_false_path -from [get_pins signal_watchdog_inst/receiver_rst_reg_reg/C]

set_false_path -from [get_pins dot11_inst/sync_long_reset_reg/C]

set_property PACKAGE_PIN T20 [get_ports SPI_nss]

set_property PACKAGE_PIN AA25 [get_ports o_dcmi_frame]
set_property IOSTANDARD LVCMOS33 [get_ports o_dcmi_frame]

connect_debug_port u_ila_0/probe25 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_0]]
connect_debug_port u_ila_0/probe26 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_1]]
connect_debug_port u_ila_0/probe27 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_2]]
connect_debug_port u_ila_0/probe28 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_3]]
connect_debug_port u_ila_0/probe29 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_4]]
connect_debug_port u_ila_0/probe30 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_21]]
connect_debug_port u_ila_0/probe31 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_22]]
connect_debug_port u_ila_0/probe32 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_23]]
connect_debug_port u_ila_0/probe33 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_24]]
connect_debug_port u_ila_0/probe34 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_25]]
connect_debug_port u_ila_0/probe35 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_26]]
connect_debug_port u_ila_0/probe36 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_27]]
connect_debug_port u_ila_0/probe37 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_28]]
connect_debug_port u_ila_0/probe38 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_29]]
connect_debug_port u_ila_0/probe39 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_30]]
connect_debug_port u_ila_0/probe40 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_31]]
connect_debug_port u_ila_0/probe41 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_32]]
connect_debug_port u_ila_0/probe42 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_33]]
connect_debug_port u_ila_0/probe43 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_34]]
connect_debug_port u_ila_0/probe44 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_35]]
connect_debug_port u_ila_0/probe45 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_36]]
connect_debug_port u_ila_0/probe46 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_53]]
connect_debug_port u_ila_0/probe47 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_54]]
connect_debug_port u_ila_0/probe48 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_55]]
connect_debug_port u_ila_0/probe49 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_56]]
connect_debug_port u_ila_0/probe50 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_57]]
connect_debug_port u_ila_0/probe51 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_58]]
connect_debug_port u_ila_0/probe52 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_59]]
connect_debug_port u_ila_0/probe53 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_60]]
connect_debug_port u_ila_0/probe54 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_61]]
connect_debug_port u_ila_0/probe55 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_62]]
connect_debug_port u_ila_0/probe56 [get_nets [list dot11_inst/equalizer_inst/rotate_inst/mult_inst_n_63]]



connect_debug_port u_ila_0/probe8 [get_nets [list o_dcmi_frame_OBUF]]

set_property PACKAGE_PIN AA25 [get_ports o_DCMI_vsync]
set_property PACKAGE_PIN W21 [get_ports o_DCMI_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports o_DCMI_hsync]
set_property IOSTANDARD LVCMOS33 [get_ports o_DCMI_vsync]


set_property PACKAGE_PIN V26 [get_ports o_DCMI_hsync]

connect_debug_port u_ila_0/probe10 [get_nets [list o_DCMI_hsync_OBUF]]


create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 8192 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 2 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list lvds_irx0/o_lvds_dclk]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 8 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {o_byteOut_OBUF[0]} {o_byteOut_OBUF[1]} {o_byteOut_OBUF[2]} {o_byteOut_OBUF[3]} {o_byteOut_OBUF[4]} {o_byteOut_OBUF[5]} {o_byteOut_OBUF[6]} {o_byteOut_OBUF[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 4 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {o_state_OBUF[0]} {o_state_OBUF[1]} {o_state_OBUF[2]} {o_state_OBUF[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 12 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {adc_q[0]} {adc_q[1]} {adc_q[2]} {adc_q[3]} {adc_q[4]} {adc_q[5]} {adc_q[6]} {adc_q[7]} {adc_q[8]} {adc_q[9]} {adc_q[10]} {adc_q[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 8 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {byte_out[0]} {byte_out[1]} {byte_out[2]} {byte_out[3]} {byte_out[4]} {byte_out[5]} {byte_out[6]} {byte_out[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 12 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {adc_i[0]} {adc_i[1]} {adc_i[2]} {adc_i[3]} {adc_i[4]} {adc_i[5]} {adc_i[6]} {adc_i[7]} {adc_i[8]} {adc_i[9]} {adc_i[10]} {adc_i[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 1 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list byte_out_strobe]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 1 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list dcmi_frame]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 1 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list fcs_out_strobe]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 1 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list o_byteOutStrobe_OBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 1 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list o_DCMI_vsync_OBUF]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 1 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list receiver_rst]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 1 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list {bufferWord[0]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 1 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list {bufferWord[1]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 1 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list {bufferWord[2]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 1 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list {bufferWord[3]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 1 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list {bufferWord[4]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe16]
set_property port_width 1 [get_debug_ports u_ila_0/probe16]
connect_debug_port u_ila_0/probe16 [get_nets [list {bufferWord[5]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe17]
set_property port_width 1 [get_debug_ports u_ila_0/probe17]
connect_debug_port u_ila_0/probe17 [get_nets [list {bufferWord[6]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe18]
set_property port_width 1 [get_debug_ports u_ila_0/probe18]
connect_debug_port u_ila_0/probe18 [get_nets [list {bufferWord[7]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe19]
set_property port_width 1 [get_debug_ports u_ila_0/probe19]
connect_debug_port u_ila_0/probe19 [get_nets [list {bufferWord[8]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe20]
set_property port_width 1 [get_debug_ports u_ila_0/probe20]
connect_debug_port u_ila_0/probe20 [get_nets [list {bufferWord[9]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe21]
set_property port_width 1 [get_debug_ports u_ila_0/probe21]
connect_debug_port u_ila_0/probe21 [get_nets [list {bufferWord[10]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe22]
set_property port_width 1 [get_debug_ports u_ila_0/probe22]
connect_debug_port u_ila_0/probe22 [get_nets [list {bufferWord[11]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe23]
set_property port_width 1 [get_debug_ports u_ila_0/probe23]
connect_debug_port u_ila_0/probe23 [get_nets [list {bufferWord[15]_i_1_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe24]
set_property port_width 1 [get_debug_ports u_ila_0/probe24]
connect_debug_port u_ila_0/probe24 [get_nets [list {bufferWord[15]_i_2_n_0}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe25]
set_property port_width 1 [get_debug_ports u_ila_0/probe25]
connect_debug_port u_ila_0/probe25 [get_nets [list {bufferWord_reg_n_0_[0]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe26]
set_property port_width 1 [get_debug_ports u_ila_0/probe26]
connect_debug_port u_ila_0/probe26 [get_nets [list {bufferWord_reg_n_0_[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe27]
set_property port_width 1 [get_debug_ports u_ila_0/probe27]
connect_debug_port u_ila_0/probe27 [get_nets [list {bufferWord_reg_n_0_[2]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe28]
set_property port_width 1 [get_debug_ports u_ila_0/probe28]
connect_debug_port u_ila_0/probe28 [get_nets [list {bufferWord_reg_n_0_[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe29]
set_property port_width 1 [get_debug_ports u_ila_0/probe29]
connect_debug_port u_ila_0/probe29 [get_nets [list {bufferWord_reg_n_0_[4]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe30]
set_property port_width 1 [get_debug_ports u_ila_0/probe30]
connect_debug_port u_ila_0/probe30 [get_nets [list {bufferWord_reg_n_0_[5]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe31]
set_property port_width 1 [get_debug_ports u_ila_0/probe31]
connect_debug_port u_ila_0/probe31 [get_nets [list {bufferWord_reg_n_0_[6]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe32]
set_property port_width 1 [get_debug_ports u_ila_0/probe32]
connect_debug_port u_ila_0/probe32 [get_nets [list {bufferWord_reg_n_0_[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe33]
set_property port_width 1 [get_debug_ports u_ila_0/probe33]
connect_debug_port u_ila_0/probe33 [get_nets [list {bufferWord_reg_n_0_[8]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe34]
set_property port_width 1 [get_debug_ports u_ila_0/probe34]
connect_debug_port u_ila_0/probe34 [get_nets [list {bufferWord_reg_n_0_[9]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe35]
set_property port_width 1 [get_debug_ports u_ila_0/probe35]
connect_debug_port u_ila_0/probe35 [get_nets [list {bufferWord_reg_n_0_[10]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe36]
set_property port_width 1 [get_debug_ports u_ila_0/probe36]
connect_debug_port u_ila_0/probe36 [get_nets [list {bufferWord_reg_n_0_[11]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe37]
set_property port_width 1 [get_debug_ports u_ila_0/probe37]
connect_debug_port u_ila_0/probe37 [get_nets [list {bufferWord_reg_n_0_[15]}]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets sample_clk]
