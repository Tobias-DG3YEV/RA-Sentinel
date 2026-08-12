#############################################################################
# rasbb_rasrf.xdc - OWIFI_RX on RASBB + 1ch RASRF (MAX2831 + ADC3221).
#
# Derived from the hardware-proven RASM2400 constraint set (RASBB_common.xdc
# + pins_RASRF.xdc @c103c5e), with:
#   - the TMDS/HDMI and spectrum-display constraints removed (no video here)
#   - the BUFG pin path adjusted for the adc_frontend hierarchy (fe0/...)
#   - the STM32<->FPGA1 SPI pins added, derived from RASBB.kicad_pcb
#     (FPGA1_CLK=E9 via R1, FPGA1_MOSI=K17 via R2, FPGA1_MISO=K18 via R4;
#     chip select is the general-purpose line F1_B15_C15=C15 through IC11 -
#     a CONVENTION defined here, the STM32 firmware must use the matching
#     GPIO).
#
# Keep the golden rules: the ADC bit clock is a TRUE 120MHz clock (8.333ns -
# never constrain it at half rate, see RASM2400 "finding D1"), and every
# used LVDS pair is EXTERNALLY terminated with 100R (HR bank: DIFF_TERM
# inert at VCCO 1.8V, IN_TERM fights the ADC's common mode).
#############################################################################

############## bitstream / config ##################
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
set_property CONFIG_MODE SPIx1 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

############## system clock / keys ##################
set_property PACKAGE_PIN E3 [get_ports SYS_clk]
set_property IOSTANDARD LVCMOS18 [get_ports SYS_clk]
create_clock -period 20.000 -name SYS_clk [get_ports SYS_clk]

set_property PACKAGE_PIN P14 [get_ports Key0]
set_property PACKAGE_PIN T15 [get_ports Key1]
set_property IOSTANDARD LVCMOS18 [get_ports Key0]
set_property IOSTANDARD LVCMOS18 [get_ports Key1]
set_property PULLTYPE PULLUP [get_ports Key0]
set_property PULLTYPE PULLUP [get_ports Key1]
set_disable_timing [get_ports Key0]
set_disable_timing [get_ports Key1]

############## ADC LVDS (RASRF pinout) ##################
# RASRF: bit clock on H1 (RASBB net RX3), frame clock on G4 (RX2) - swapped
# versus the BMC frontend. I data (DA0) on F1/E1 (RX5), Q data (DB0) on
# K2/K1 (RX1) = port ADC_chC; chB (H2/G2, RX4) is RASRF's unused DA1.
set_property PACKAGE_PIN H1 [get_ports ADC_dclk_P]
set_property PACKAGE_PIN G4 [get_ports ADC_fclk_P]
set_property PACKAGE_PIN F1 [get_ports ADC_chA_P]
set_property PACKAGE_PIN E1 [get_ports ADC_chA_N]
set_property PACKAGE_PIN H2 [get_ports ADC_chB_P]
set_property PACKAGE_PIN G2 [get_ports ADC_chB_N]
set_property PACKAGE_PIN K2 [get_ports ADC_chC_P]
set_property PACKAGE_PIN K1 [get_ports ADC_chC_N]

set_property IOSTANDARD DIFF_SSTL18_II [get_ports ADC_chA_P]
set_property IOSTANDARD DIFF_SSTL18_II [get_ports ADC_chB_P]
set_property IOSTANDARD DIFF_SSTL18_II [get_ports ADC_chC_P]
set_property IOSTANDARD DIFF_SSTL18_II [get_ports ADC_dclk_P]
set_property IOSTANDARD DIFF_SSTL18_II [get_ports ADC_fclk_P]

############## clocks ##################
# One-wire, 20MSPS: DCLK = 6 x fS = 120MHz true period, FCLK = fS = 20MHz.
create_clock -period 8.333 -name ADC_dclk_P -waveform {0.000 4.167} -add [get_ports ADC_dclk_P]
create_clock -period 8.333 -name lvds_dclk_buffered -waveform {0.000 4.167} [get_pins fe0/BUFG_lvds_dclk_1/O]

# ADC-side clocks derive from the frontend's oscillator, everything else from
# the RASBB 50MHz - different crystals, genuinely asynchronous.
set_clock_groups -asynchronous -group [get_clocks {ADC_dclk_P lvds_dclk_buffered}]

# DCLK is not on an MRCC/SRCC pair - relax the dedicated-route DRC for the
# IBUFDS->BUFG hop (IBUFDS_DIFF_OUT decomposes, match by substring).
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ "*lvds_irx0/IBUFDS_adc_dclk*"}]

# FCLK is captured as DATA (ISERDES pipeline + 2-FF sync), never used as a
# clock: false path, the word-rotation calibration absorbs the offset.
set_false_path -from [get_ports ADC_fclk_P]

# ADC pad hold fix-up path
set_multicycle_path -from [get_ports {ADC_dclk_N ADC_dclk_P}] -to [get_pins -hierarchical *DDLY*] 1

# Source-synchronous input timing, ADC3424 SBAS673A Table 2 (25MSPS row):
# tSU 1.3ns / tHO 1.32ns against each DCLK half-period edge.
set_input_delay -clock [get_clocks ADC_dclk_P] -min 1.320 [get_ports {ADC_chA_P ADC_chB_P ADC_chC_P}]
set_input_delay -clock [get_clocks ADC_dclk_P] -max 2.867 [get_ports {ADC_chA_P ADC_chB_P ADC_chC_P}]
set_input_delay -clock [get_clocks ADC_dclk_P] -clock_fall -min 1.320 -add_delay [get_ports {ADC_chA_P ADC_chB_P ADC_chC_P}]
set_input_delay -clock [get_clocks ADC_dclk_P] -clock_fall -max 2.867 -add_delay [get_ports {ADC_chA_P ADC_chB_P ADC_chC_P}]

# Hold is analysed with the IDELAYE2 at its build-time tap, but the taps on
# these lanes are swept and re-centred by the runtime calibration, so the
# static min-delay number says nothing about the calibrated eye. Every
# proven bitstream (_OK, build_rasbb_v4) carries the same ~-0.25ns pad hold.
# Exclude hold only - setup stays analysed - so a real hold regression
# elsewhere is visible and the router does not pad these nets against the
# calibration.
set_false_path -hold -from [get_ports {ADC_chA_P ADC_chB_P ADC_chC_P}]

############## SPI (STM32H743 is master; quasi-static config only) ##########
# There is NO dedicated uC<->FPGA1 SPI on RASBB: the runtime channel is the
# SHARED FLASH BUS (RASBB.kicad_pcb): the uC's flash SPI lands on FPGA1 user
# pins SCK=D18 (SCK_FLASH_uC), SI/COPI=E17, SO/CIPO=D17, and the uC's flash
# select CS_FLASH_uC=E18 doubles as the FPGA1 select - the TS3A5018 mux
# (IC6, MUX_EN1/SWITCH_FLASH_1 from the uC) steers the flash on or off the
# bus. Firmware discipline: park the mux away from the flash before talking
# to the FPGA. The FPGA tristates CIPO while deselected (see system_top) so
# flash traffic never sees contention on D17.
# (FPGA1_CLK/MOSI/MISO at E9/K17/K18 are the uC's CONFIGURATION path - E9
# is the dedicated CCLK ball, not LOCable by user logic.)
set_property PACKAGE_PIN D18 [get_ports SPI_sclk]
set_property PACKAGE_PIN E17 [get_ports SPI_copi]
set_property PACKAGE_PIN D17 [get_ports SPI_cipo]
set_property PACKAGE_PIN E18 [get_ports SPI_ncs]
# Bank 15 VCCO is +3V3 (PCB-verified 2026-08-02) and the STM32H743 on the
# other end is a 3.3V part, so these are LVCMOS33. They were LVCMOS18, which
# only appeared to work because a 1.8V input threshold still triggers on a
# 3.3V swing.
set_property IOSTANDARD LVCMOS33 [get_ports SPI_sclk]
set_property IOSTANDARD LVCMOS33 [get_ports SPI_copi]
set_property IOSTANDARD LVCMOS33 [get_ports SPI_cipo]
set_property IOSTANDARD LVCMOS33 [get_ports SPI_ncs]
set_property PULLTYPE PULLUP [get_ports SPI_ncs]
# spi_frame_if OVERSAMPLES sclk/copi/ncs in the 100MHz receiver clock instead
# of clocking on sclk (SPI_Peripheral did the latter, which needed a
# CLOCK_DEDICATED_ROUTE waiver and a BUFG on a fabric route because D18 is not
# clock-capable). There is therefore no SPI clock domain at all: all four pins
# are plain asynchronous I/O behind 3-stage synchronisers.
# HARD LIMIT: 8 fabric clocks per SPI bit -> the STM32 must keep SCLK <= 12.5MHz.
set_false_path -from [get_ports {SPI_copi SPI_ncs SPI_sclk}]
set_false_path -to   [get_ports SPI_cipo]

############## HDMI (frame log) ##################
# Pins derived from RASBB.kicad_pcb, NOT from RASM2400.xdc: that file maps
# TMDS onto D4/C4/E1/D1/F2/E2/G2, which on THIS board are PCIe RX lanes, GND
# and +1V8 - it is a leftover from the Wukong devboard and would collide with
# ADC_chA_N (E1) and ADC_chB_N (G2). See [rasbb-pcb-net-desync]: derive pins
# from the .kicad_pcb, never from a stale constraint set.
#   U10 A13/A14 = HDMI_CLK_P/N, B16/B17 = D0, A15/A16 = D1, B18/A18 = D2
set_property PACKAGE_PIN A13 [get_ports TMDS_clk_p]
set_property PACKAGE_PIN A14 [get_ports TMDS_clk_n]
set_property PACKAGE_PIN B16 [get_ports {TMDS_data_p[0]}]
set_property PACKAGE_PIN B17 [get_ports {TMDS_data_n[0]}]
set_property PACKAGE_PIN A15 [get_ports {TMDS_data_p[1]}]
set_property PACKAGE_PIN A16 [get_ports {TMDS_data_n[1]}]
set_property PACKAGE_PIN B18 [get_ports {TMDS_data_p[2]}]
set_property PACKAGE_PIN A18 [get_ports {TMDS_data_n[2]}]
# TMDS_33, the real standard for this link, as RASM2400/RASPMO/LOTAG_SPMO
# already use on the same pins. Bank 15 is a 3.3V bank (the earlier
# DIFF_SSTL18_* constraints here assumed 1.8V - wrong, PCB-verified
# 2026-08-02). DIFF_SSTL18_II+FAST mostly locked the monitor but was
# margin-of-the-day: on 2026-08-02 both proven bitstreams went dark on an
# unchanged board while a TMDS_33 design locked, and a TMDS_33 ECO of the
# same routed.dcp locked again. It also becomes actively dangerous the
# moment the planned 100nF TMDS AC-coupling rework goes in (re-centered
# push-pull swing exceeds the sink's abs-max). Do not go back.
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_clk_p TMDS_clk_n}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[*] TMDS_data_n[*]}]

# TMDS/DVI is source-synchronous: the clock leaves the chip through the SAME
# OSERDES structure as the data, so pin-to-pin skew is matched by construction.
# Timing the data pins against an implied receiver clock only manufactures
# violations - leaving this out cost WNS -10.557ns on the 325MHz serial clock,
# which looks like a catastrophic design fault and is purely an artefact.
# (Same constraint and reasoning as RASM2400's RASBB_common.xdc.)
set_false_path -to [get_ports {TMDS_clk_p TMDS_clk_n TMDS_data_p[*] TMDS_data_n[*]}]

# (The SLEW FAST that lived here belonged to the DIFF_SSTL18 era - TMDS_33
# is current-mode and takes no SLEW/DRIVE attributes.)

# The scroll pointer is the ONLY signal crossing from the receiver's 100MHz
# domain into the 65MHz pixel domain (frame text crosses inside a dual-port
# BRAM, which needs no timing arc). It is gray-coded and double-synchronised,
# so the crossing itself must not be timed - both clocks descend from SYS_clk
# and would otherwise be treated as synchronous.
set_false_path -from [get_cells -hierarchical -filter {NAME =~ "*frame_log_inst/top_row_reg*"}] \
               -to   [get_cells -hierarchical -filter {NAME =~ "*text_screen_inst/top_g0_reg*"}]

############## J5 debug header ##################
set_property PACKAGE_PIN T10 [get_ports dbgBitClk]
set_property PACKAGE_PIN T11 [get_ports dbgFrameRdy]
set_property PACKAGE_PIN T13 [get_ports dbgIser]
set_property PACKAGE_PIN R13 [get_ports dbgQser]
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
set_property PACKAGE_PIN U17 [get_ports {dbgOutI[11]}]
set_property PACKAGE_PIN U18 [get_ports {dbgOutQ[0]}]
set_property PACKAGE_PIN T18 [get_ports {dbgOutQ[1]}]
set_property PACKAGE_PIN R17 [get_ports {dbgOutQ[2]}]
set_property PACKAGE_PIN R18 [get_ports {dbgOutQ[3]}]
set_property PACKAGE_PIN L18 [get_ports {dbgOutQ[4]}]
set_property PACKAGE_PIN M18 [get_ports {dbgOutQ[5]}]
set_property PACKAGE_PIN M17 [get_ports {dbgOutQ[6]}]
set_property PACKAGE_PIN N17 [get_ports {dbgOutQ[7]}]
set_property PACKAGE_PIN P18 [get_ports {dbgOutQ[8]}]
set_property PACKAGE_PIN P17 [get_ports {dbgOutQ[9]}]
set_property PACKAGE_PIN N14 [get_ports {dbgOutQ[10]}]
set_property PACKAGE_PIN M14 [get_ports {dbgOutQ[11]}]
set_property IOSTANDARD LVCMOS18 [get_ports {dbgBitClk dbgFrameRdy dbgIser dbgQser dbgOutI[*] dbgOutQ[*]}]
set_property DRIVE 24 [get_ports {dbgBitClk dbgFrameRdy dbgIser dbgQser dbgOutI[*] dbgOutQ[*]}]
set_property SLEW FAST [get_ports {dbgBitClk dbgFrameRdy dbgIser dbgQser dbgOutI[*] dbgOutQ[*]}]
set_property OFFCHIP_TERM NONE [get_ports {dbgBitClk dbgFrameRdy dbgIser dbgQser}]
set_false_path -to [get_ports {dbgOutI[*] dbgOutQ[*] dbgBitClk dbgFrameRdy dbgIser dbgQser}]

############## resets ##################
set_false_path -to [get_pins -hierarchical -filter {IS_CLEAR || IS_PRESET || IS_RESET}]
set_false_path -from [get_cells -hierarchical -filter {NAME =~ "*global_rst_reg*"}]
