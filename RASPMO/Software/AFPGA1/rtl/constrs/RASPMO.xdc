############## Target: RASBB onboard FPGA, XC7A100T-CSG324 ##################
#
# This is U10, the HDMI-driving FPGA (U11 is the other one). Pins verified on
# real Rev.A silicon by scope/trace - trust them over any netlist.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
set_property CONFIG_MODE SPIx1 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

############## SYS_clk - 50MHz oscillator, bank 35 @ 1.8V, ball E3 (MRCC) ####
set_property PACKAGE_PIN E3 [get_ports i_SYS_clk]
set_property IOSTANDARD LVCMOS18 [get_ports i_SYS_clk]
create_clock -period 20.000 -name SYS_clk -waveform {0.000 10.000} [get_ports i_SYS_clk]

############## ADC1 LVDS interface, bank 35 @ 1.8V ###########################
# ADC3424 one-wire, 20MSPS, low-speed DDR: 12 bits over 6 DCLK cycles on both
# phases -> DCLK = 6 x fS = 120MHz, FCLK = fS = 20MHz.
#
# _I and NOT _II. The ADC3424 wants external 100R termination and this board
# has it. _II adds Xilinx DCI on-die termination on top, and two termination
# networks fighting each other drag the signal under the receiver threshold -
# while still looking perfectly clean on a scope probe, which is high impedance
# and doesn't load the line the way DCI does. Don't "fix" this to _II.

set_property PACKAGE_PIN G4 [get_ports i_ADC_dclk_P]
set_property PACKAGE_PIN G3 [get_ports i_ADC_dclk_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC_dclk_P]

set_property PACKAGE_PIN H1 [get_ports i_ADC_fclk_P]
set_property PACKAGE_PIN G1 [get_ports i_ADC_fclk_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC_fclk_P]

set_property PACKAGE_PIN F1 [get_ports i_ADC_chA_P] ;# ADC1 channel A = I
set_property PACKAGE_PIN E1 [get_ports i_ADC_chA_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC_chA_P]

set_property PACKAGE_PIN H2 [get_ports i_ADC_chB_P] ;# ADC1 channel B = RX1 Q
set_property PACKAGE_PIN G2 [get_ports i_ADC_chB_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC_chB_P]

# ADC1 channels C/D = RX2 I/Q.
set_property PACKAGE_PIN K2 [get_ports i_ADC_chC_P] ;# ADC1 channel C = RX2 I
set_property PACKAGE_PIN K1 [get_ports i_ADC_chC_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC_chC_P]

set_property PACKAGE_PIN J3 [get_ports i_ADC_chD_P] ;# ADC1 channel D = RX2 Q
set_property PACKAGE_PIN J2 [get_ports i_ADC_chD_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC_chD_P]

############## ADC2 LVDS interface, bank 35 @ 1.8V ###########################
# Second ADC3424, RX3/RX4 baseband. Same electrical setup as ADC1.
#
# !! NO TERMINATION ON THE BASEBOARD !! Like every RX pair, each of these needs
# a hand-soldered 100R across it near U10, same as chA/chB got. Until then the
# lanes are garbage - harmless, the affected panes just show noise.
set_property PACKAGE_PIN E6 [get_ports i_ADC2_dclk_P]
set_property PACKAGE_PIN E5 [get_ports i_ADC2_dclk_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC2_dclk_P]

set_property PACKAGE_PIN B3 [get_ports i_ADC2_fclk_P]
set_property PACKAGE_PIN B2 [get_ports i_ADC2_fclk_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC2_fclk_P]

set_property PACKAGE_PIN A4 [get_ports i_ADC2_chA_P] ;# ADC2 channel A = RX3 I
set_property PACKAGE_PIN A3 [get_ports i_ADC2_chA_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC2_chA_P]

set_property PACKAGE_PIN C2 [get_ports i_ADC2_chB_P] ;# ADC2 channel B = RX3 Q
set_property PACKAGE_PIN C1 [get_ports i_ADC2_chB_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC2_chB_P]

set_property PACKAGE_PIN B1 [get_ports i_ADC2_chC_P] ;# ADC2 channel C = RX4 I
set_property PACKAGE_PIN A1 [get_ports i_ADC2_chC_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC2_chC_P]

set_property PACKAGE_PIN F4 [get_ports i_ADC2_chD_P] ;# ADC2 channel D = RX4 Q
set_property PACKAGE_PIN F3 [get_ports i_ADC2_chD_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports i_ADC2_chD_P]

create_clock -period 8.333 -name ADC_dclk_P -waveform {0.000 4.167} -add [get_ports i_ADC_dclk_P]
create_clock -period 8.333 -name ADC2_dclk_P -waveform {0.000 4.167} -add [get_ports i_ADC2_dclk_P]

# FCLK deliberately gets NO create_clock - it never clocks anything, lvds_rx
# and adc_sequencer only ever sample it as data on DCLK-clocked flops. Declare
# it and Vivado invents a bogus inter-clock hold path against DCLK. It is fully
# constrained below by set_input_delay relative to DCLK instead.

# DCLK P/N are not on a clock-capable (MRCC/SRCC) pair on this board, so getting
# IBUFDS_DIFF_OUT to its BUFG needs the dedicated-route DRC relaxed. Fixed pin
# placement, not a leftover experiment. Match by hierarchy substring: the
# IBUFDS_DIFF_OUT decomposes into a sub-cell during synthesis and the
# pre-synthesis net path no longer exists.
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ "*lvds_irx0/IBUFDS_adc_dclk*"}]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ "*lvds_irx1/IBUFDS_adc_dclk*"}]

# IDELAYE2 DDLY taps are asynchronous taps off the data path, not a normal
# clock-relative register path.
set_multicycle_path -from [get_ports {i_ADC_dclk_N i_ADC_dclk_P}] -to [get_pins -hierarchical *DDLY*] 1
set_multicycle_path -from [get_ports {i_ADC2_dclk_N i_ADC2_dclk_P}] -to [get_pins -hierarchical *DDLY*] 1

# Source-synchronous input timing for the Dx0 lanes. Numbers from SBAS673A
# 7.14 Table 2 (12X serialization, 1-wire - what REG_OUTPUTMODE_1WIRE gives us),
# 25MSPS row: tSU_min = 1.3ns, tHO_min = 1.32ns, both to a DCLK edge (Fig 131).
# We run 20MSPS and margin only improves at lower rates, so that row is a safe
# floor. 1-wire clocks one bit per DCLK HALF period (4.167ns @ 120MHz) on both
# edges, hence rising AND falling constrained - EVEN takes one phase, ODD the
# other, see lvds_rx.v.
#   max = T_half - tSU_min = 4.167 - 1.3 = 2.867ns
#   min = tHO_min                        = 1.320ns
set_input_delay -clock [get_clocks ADC_dclk_P] -min 1.320 [get_ports {i_ADC_chA_P i_ADC_chB_P i_ADC_chC_P i_ADC_chD_P}]
set_input_delay -clock [get_clocks ADC_dclk_P] -max 2.867 [get_ports {i_ADC_chA_P i_ADC_chB_P i_ADC_chC_P i_ADC_chD_P}]
set_input_delay -clock [get_clocks ADC_dclk_P] -clock_fall -min 1.320 -add_delay [get_ports {i_ADC_chA_P i_ADC_chB_P i_ADC_chC_P i_ADC_chD_P}]
set_input_delay -clock [get_clocks ADC_dclk_P] -clock_fall -max 2.867 -add_delay [get_ports {i_ADC_chA_P i_ADC_chB_P i_ADC_chC_P i_ADC_chD_P}]

set_input_delay -clock [get_clocks ADC2_dclk_P] -min 1.320 [get_ports {i_ADC2_chA_P i_ADC2_chB_P i_ADC2_chC_P i_ADC2_chD_P}]
set_input_delay -clock [get_clocks ADC2_dclk_P] -max 2.867 [get_ports {i_ADC2_chA_P i_ADC2_chB_P i_ADC2_chC_P i_ADC2_chD_P}]
set_input_delay -clock [get_clocks ADC2_dclk_P] -clock_fall -min 1.320 -add_delay [get_ports {i_ADC2_chA_P i_ADC2_chB_P i_ADC2_chC_P i_ADC2_chD_P}]
set_input_delay -clock [get_clocks ADC2_dclk_P] -clock_fall -max 2.867 -add_delay [get_ports {i_ADC2_chA_P i_ADC2_chB_P i_ADC2_chC_P i_ADC2_chD_P}]

# Pad hold gets analysed against the BUILD-TIME IDELAY tap, but link_supervisor
# sweeps and re-centres the taps at runtime, so the static number says nothing
# about the eye we actually run in. Every good build has carried a modeled
# -0.26..-0.48ns here while running error-free.
# Hold only. Setup stays analysed.
set_false_path -hold -from [get_ports {i_ADC_chA_P i_ADC_chB_P i_ADC_chC_P i_ADC_chD_P i_ADC2_chA_P i_ADC2_chB_P i_ADC2_chC_P i_ADC2_chD_P}]

# FCLK isn't in Table 2 - it's a per-frame status level, not a per-bit serial
# line. adc_sequencer's preSync FSM only ever samples it as data and is built to
# find the transition by watching it over several DCLK cycles; it doesn't care
# about catching one exact edge. There is genuinely no sub-ns requirement to
# express here, so don't try to tune a set_input_delay window - the worst path
# just hops to a different preSync bit with a different routed delay on every
# re-place. False path, full stop.
set_false_path -from [get_ports i_ADC_fclk_P]
set_false_path -from [get_ports i_ADC2_fclk_P]

# The ADC DCLKs run free off the front-end's 40MHz TCXO, totally independent of
# RASBB's 50MHz oscillator and everything derived from it. Both DCLKs share that
# TCXO but go through separate in-ADC PLLs, so their phase relation is unknown
# too - the design only ever crosses them through the gray-pointer sample_cdc
# FIFO. Every inter-group path goes via a dual-clock memory or a real
# synchroniser, so analysis between these groups is meaningless and must be
# excluded rather than left to pass or fail by luck.
#
# Fourth group, the subtle one: hdmi_clk.v shares the SYS_clk port with the
# Video_clk IP, so synthesis pulls the IP's input behind a common IBUF and the
# IP's own XDC roots its clocks under an auto-created master
# ("video_clk0/inst/i_clk_50M") instead of SYS_clk. "-include_generated_clocks
# SYS_clk" then misses clk_120M/clk_195M and the deliberately-async ILA snapshot
# paths (ADC domain -> dbg_* on clk_120M) get timed for real: WNS -8.5ns. The
# only clk_120M <-> pixel paths are that ILA capture and the reset fanout, both
# explicitly false-pathed, so giving the Video_clk family its own async group is
# exact, not a fudge.
# -quiet so a changed IP config that renames a clock doesn't break the build.
set_clock_groups -asynchronous \
    -group [get_clocks ADC_dclk_P] \
    -group [get_clocks ADC2_dclk_P] \
    -group [get_clocks -include_generated_clocks SYS_clk] \
    -group [get_clocks -quiet {video_clk0/inst/i_clk_50M clkfbout_Video_clk o_clk_120M_Video_clk o_clk_195M_Video_clk o_clk_65M_Video_clk o_clk_325M_Video_clk}]

############## HDMI output, bank 15 @ 3.3V ####################################
set_property PACKAGE_PIN A13 [get_ports o_TMDS_clk_p]
set_property PACKAGE_PIN A14 [get_ports o_TMDS_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports o_TMDS_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports o_TMDS_clk_n]

set_property PACKAGE_PIN B16 [get_ports {o_TMDS_data_p[0]}]
set_property PACKAGE_PIN B17 [get_ports {o_TMDS_data_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {o_TMDS_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {o_TMDS_data_n[0]}]

set_property PACKAGE_PIN A15 [get_ports {o_TMDS_data_p[1]}]
set_property PACKAGE_PIN A16 [get_ports {o_TMDS_data_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {o_TMDS_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {o_TMDS_data_n[1]}]

set_property PACKAGE_PIN B18 [get_ports {o_TMDS_data_p[2]}]
set_property PACKAGE_PIN A18 [get_ports {o_TMDS_data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {o_TMDS_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {o_TMDS_data_n[2]}]

set_output_delay -clock [get_clocks -include_generated_clocks SYS_clk] -min -add_delay -0.538 [get_ports {o_TMDS_data_n[*] o_TMDS_data_p[*] o_TMDS_clk_n o_TMDS_clk_p}]
set_output_delay -clock [get_clocks -include_generated_clocks SYS_clk] -max -add_delay 2.538 [get_ports {o_TMDS_data_n[*] o_TMDS_data_p[*] o_TMDS_clk_n o_TMDS_clk_p}]

############## Asynchronous reset #############################################
# global_rst is one power-up pulse made in clk_120M and fanned out as an async
# reset into flops in every other domain. Nothing about its assert/deassert is
# meant to be cycle-accurate anywhere - it just has to eventually go away. So
# neither recovery/removal (when synthesis puts it on a dedicated clear/preset
# pin) nor plain setup/hold (when it instead folds into fabric logic on a D
# input, e.g. screen.v's "if(i_rst) ... else ...") means anything.
# False-path everything downstream of the generating register, covers both.
set_false_path -to [get_pins -hierarchical -filter {IS_CLEAR || IS_PRESET || IS_RESET}]
set_false_path -from [get_cells -hierarchical -filter {NAME =~ "*global_rst_reg*"}]
# the deserializer self-heal reset (top.v fe_rst block) crosses clk_120M ->
# both DCLK domains the same way global_rst does - same blanket exception
set_false_path -from [get_cells -hierarchical -filter {NAME =~ "*heal_rst_reg*"}]

# Some of the ILA-probed nets (video_hs/vs/de) are in the pixel-clock domain
# while the ILA itself samples on clk_120M, ILA is still an unexpanded IP blackbox,
# so we need to set the false path here.
set_false_path -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ "*hdmi_clk0*mmcm_hdmi*CLKOUT1"}]] -to [get_clocks o_clk_120M_Video_clk]
