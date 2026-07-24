############## Target: RASBB onboard FPGA, XC7A100T-CSG324 ##################
#
# IMPORTANT: RASBB.net (the schematic-exported netlist) and RASBB.kicad_pcb
# (the actual PCB layout) have desynced reference designators. RASBB.net's
# "U1" is NOT the FPGA on the fabricated board - tracing it in the PCB layout
# lands on a diode footprint instead. The two FPGAs on the real board are
# U10 (this one; drives HDMI, per the block diagram) and U11. All pin numbers
# below come from directly reading U10's pads in RASBB.kicad_pcb (its actual
# routed copper), not from RASBB.net - and were cross-validated against the
# empirically-verified pins in AP_FPGA_TEST's RASBB_AP.xdc (confirmed working
# HDMI output on real Rev.A hardware) and against direct oscilloscope/trace
# verification on this specific board, both of which agree with this data.
#
# This also means the original RASBB_AP.xdc pin assignments inherited from
# RASM2400 (F1/E1 for chA, K2/K1 for chC, G4 for dclk_P, H1 for fclk_P) were
# actually correct all along; they were wrongly discarded earlier in this
# project based on tracing the desynced RASBB.net "U1" instead of U10.

set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.CONFIG.UNUSEDPIN PULLUP [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 1 [current_design]
set_property CONFIG_MODE SPIx1 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 50 [current_design]

############## SYS_clk - 50MHz oscillator, bank 35 @ 1.8V, ball E3 (MRCC) ####
set_property PACKAGE_PIN E3 [get_ports SYS_clk]
set_property IOSTANDARD LVCMOS18 [get_ports SYS_clk]
create_clock -period 20.000 -name SYS_clk -waveform {0.000 10.000} [get_ports SYS_clk]

############## ADC1 LVDS interface, bank 35 @ 1.8V ###########################
# ADC3424 one-wire, 20MSPS, low-speed (DDR) mode: 12 bits captured over 6
# DCLK cycles using both clock phases -> DCLK = 6 x fS = 120MHz, FCLK = fS = 20MHz.
#
# DIFF_SSTL18_I, not _II: the ADC3424 datasheet specifies external 100 ohm
# termination for its LVDS outputs (confirmed present on this board by scope
# measurement at the connector). _II enables Xilinx's internal DCI on-die
# termination in addition to that - two termination networks fighting each
# other can attenuate the signal enough to fail the receiver's input
# threshold even though it still looks clean on an external scope probe
# (high impedance, doesn't load the line the way DCI does).

set_property PACKAGE_PIN G4 [get_ports ADC_dclk_P]
set_property PACKAGE_PIN G3 [get_ports ADC_dclk_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_dclk_P]

set_property PACKAGE_PIN H1 [get_ports ADC_fclk_P]
set_property PACKAGE_PIN G1 [get_ports ADC_fclk_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_fclk_P]

set_property PACKAGE_PIN F1 [get_ports ADC_chA_P] ;# ADC1 channel A = I
set_property PACKAGE_PIN E1 [get_ports ADC_chA_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_chA_P]

set_property PACKAGE_PIN H2 [get_ports ADC_chB_P] ;# ADC1 channel B = RX1 Q
set_property PACKAGE_PIN G2 [get_ports ADC_chB_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_chB_P]

# ADC1 channels C/D (= RX2 I/Q). Balls read from U10's pads in RASBB.kicad_pcb
# (RX1 pair = K2/K1, RX0 pair = J3/J2), cross-checked against the front-end
# card's J7 netlist (RASRF2400WBMC_Rev01.kicad_pcb: DC0 -> edge B15/B14 = RX1,
# DD0 -> edge A13/A14 = RX0) - and K2/K1 also matches the historical
# RASBB_AP.xdc "chC" assignment.
set_property PACKAGE_PIN K2 [get_ports ADC_chC_P] ;# ADC1 channel C = RX2 I
set_property PACKAGE_PIN K1 [get_ports ADC_chC_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_chC_P]

set_property PACKAGE_PIN J3 [get_ports ADC_chD_P] ;# ADC1 channel D = RX2 Q
set_property PACKAGE_PIN J2 [get_ports ADC_chD_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC_chD_P]

############## ADC2 LVDS interface, bank 35 @ 1.8V ###########################
# Second ADC3424 (RX3/RX4 baseband). Same electrical setup as ADC1; balls
# traced through RASBB.kicad_pcb (J4 RX6..RX11 pairs) matched to the front-end
# J7 assignment (DCLK -> A30/A29 = RX8, FCLK -> B34/B33 = RX9, DA0 -> B38/B37
# = RX11, DB0 -> A36/A35 = RX10, DC0 -> B27/B28 = RX7, DD0 -> A25/A26 = RX6).
#
# NOTE like every other RX pair, these have NO termination on the baseboard -
# each needs a hand-soldered 100 ohm across the pair near U10, exactly like
# chA/chB got. Until terminated, these lanes deliver garbage (harmless to the
# design: the affected panes just show noise).
set_property PACKAGE_PIN E6 [get_ports ADC2_dclk_P]
set_property PACKAGE_PIN E5 [get_ports ADC2_dclk_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC2_dclk_P]

set_property PACKAGE_PIN B3 [get_ports ADC2_fclk_P]
set_property PACKAGE_PIN B2 [get_ports ADC2_fclk_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC2_fclk_P]

set_property PACKAGE_PIN A4 [get_ports ADC2_chA_P] ;# ADC2 channel A = RX3 I
set_property PACKAGE_PIN A3 [get_ports ADC2_chA_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC2_chA_P]

set_property PACKAGE_PIN C2 [get_ports ADC2_chB_P] ;# ADC2 channel B = RX3 Q
set_property PACKAGE_PIN C1 [get_ports ADC2_chB_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC2_chB_P]

set_property PACKAGE_PIN B1 [get_ports ADC2_chC_P] ;# ADC2 channel C = RX4 I
set_property PACKAGE_PIN A1 [get_ports ADC2_chC_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC2_chC_P]

set_property PACKAGE_PIN F4 [get_ports ADC2_chD_P] ;# ADC2 channel D = RX4 Q
set_property PACKAGE_PIN F3 [get_ports ADC2_chD_N]
set_property IOSTANDARD DIFF_SSTL18_I [get_ports ADC2_chD_P]

create_clock -period 8.333 -name ADC_dclk_P -waveform {0.000 4.167} -add [get_ports ADC_dclk_P]
create_clock -period 8.333 -name ADC2_dclk_P -waveform {0.000 4.167} -add [get_ports ADC2_dclk_P]

# ADC_fclk_P is NOT declared as its own create_clock: it never clocks
# anything (lvds_rx.v and adc_sequencer.v both only ever sample it as
# ordinary data, on flip-flops clocked by ADC_dclk_P). Declaring it as a
# clock made Vivado analyze a spurious inter-clock hold path between it and
# ADC_dclk_P as if it were a real CDC race; it is fully and correctly
# constrained below via set_input_delay relative to ADC_dclk_P instead.

# ADC_dclk_P/N are not on a clock-capable (MRCC/SRCC) pair on this board, so
# routing the IBUFDS_DIFF_OUT output to the BUFG that fans it out needs the
# dedicated-route DRC relaxed. This is a real hardware constraint (fixed pin
# placement), not a leftover experiment. IBUFDS_DIFF_OUT gets decomposed into
# a sub-cell during synthesis, so match by hierarchy substring rather than an
# exact pre-synthesis net path (which does not exist post-synthesis).
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ "*lvds_irx0/IBUFDS_adc_dclk*"}]
set_property CLOCK_DEDICATED_ROUTE FALSE [get_nets -hierarchical -filter {NAME =~ "*lvds_irx1/IBUFDS_adc_dclk*"}]

# IDELAYE2 DDLY taps are asynchronous taps off the data path, not a normal
# clock-relative register path.
set_multicycle_path -from [get_ports {ADC_dclk_N ADC_dclk_P}] -to [get_pins -hierarchical *DDLY*] 1
set_multicycle_path -from [get_ports {ADC2_dclk_N ADC2_dclk_P}] -to [get_pins -hierarchical *DDLY*] 1

# Source-synchronous input timing for the Dx0 data lines, from the TI ADC3424
# datasheet (SBAS673A), Section 7.14 "Timing Requirements: LVDS Output",
# Table 2 "LVDS Timings at Lower Sampling Frequencies: 12X Serialization
# (1-Wire Mode)" - the mode REG_OUTPUTMODE_1WIRE actually configures on this
# board (see adc3424.c). Using the 25 MSPS row (nearest documented point to
# our actual 20 MSPS; margin only improves at lower sampling rates, so this is
# a safe floor, not an exact match): tSU_min = 1.3ns, tHO_min = 1.32ns,
# both referenced to a DCLK edge (Figure 131). Per Figure 130, 1-wire mode
# clocks one data bit per DCLK *half*-period (4.167ns @ 120MHz), using both
# edges - so both the rising- and falling-edge-referenced delays are
# constrained (EVEN captures off one phase, ODD off the other; see lvds_rx.v).
#   max = T_half - tSU_min = 4.167 - 1.3   = 2.867ns
#   min = tHO_min                          = 1.320ns
set_input_delay -clock [get_clocks ADC_dclk_P] -min 1.320 [get_ports {ADC_chA_P ADC_chB_P ADC_chC_P ADC_chD_P}]
set_input_delay -clock [get_clocks ADC_dclk_P] -max 2.867 [get_ports {ADC_chA_P ADC_chB_P ADC_chC_P ADC_chD_P}]
set_input_delay -clock [get_clocks ADC_dclk_P] -clock_fall -min 1.320 -add_delay [get_ports {ADC_chA_P ADC_chB_P ADC_chC_P ADC_chD_P}]
set_input_delay -clock [get_clocks ADC_dclk_P] -clock_fall -max 2.867 -add_delay [get_ports {ADC_chA_P ADC_chB_P ADC_chC_P ADC_chD_P}]

set_input_delay -clock [get_clocks ADC2_dclk_P] -min 1.320 [get_ports {ADC2_chA_P ADC2_chB_P ADC2_chC_P ADC2_chD_P}]
set_input_delay -clock [get_clocks ADC2_dclk_P] -max 2.867 [get_ports {ADC2_chA_P ADC2_chB_P ADC2_chC_P ADC2_chD_P}]
set_input_delay -clock [get_clocks ADC2_dclk_P] -clock_fall -min 1.320 -add_delay [get_ports {ADC2_chA_P ADC2_chB_P ADC2_chC_P ADC2_chD_P}]
set_input_delay -clock [get_clocks ADC2_dclk_P] -clock_fall -max 2.867 -add_delay [get_ports {ADC2_chA_P ADC2_chB_P ADC2_chC_P ADC2_chD_P}]

# FCLK is not covered by Table 2 (it is a per-frame status level, not a
# per-bit serial line). It is only ever sampled as ordinary data by
# adc_sequencer's preSync state machine, which is explicitly built to locate
# the FCLK transition by watching it across several DCLK cycles - it does not
# depend on capturing any specific edge in one exact cycle. A tuned
# set_input_delay window kept chasing a moving target here (the worst-case
# path shifted to a different bit of the preSync register, with a different
# routed delay, on every placement re-run) because there genuinely is no
# sub-ns timing requirement to express - so this is a false path, not a
# timing budget to get right.
set_false_path -from [get_ports ADC_fclk_P]
set_false_path -from [get_ports ADC2_fclk_P]

# The ADCs' 120MHz DCLKs are free-running from the RF front-end's own 40MHz
# TCXO, entirely independent of RASBB's 50MHz FPGA oscillator (and everything
# derived from it: pixel/serial/IDELAY clocks). The two ADC DCLKs come from
# the same TCXO but through separate in-ADC PLLs, so their phase relation is
# also unknown (the design crosses them only through the gray-pointer
# sample_cdc FIFO). All inter-group paths are handled by dual-clock memories
# or proper synchronizers - timing analysis between these groups is
# meaningless and must be excluded, not left to accidentally pass or fail.
# NOTE on the fourth group: since hdmi_clk.v shares the SYS_clk port with the
# Video_clk IP, synthesis moved the IP's input behind a common external IBUF
# and the IP's own XDC now roots its clocks under a separate auto-created
# master clock ("video_clk0/inst/i_clk_50M") instead of SYS_clk - so
# "-include_generated_clocks SYS_clk" no longer covers clk_120M/clk_195M, and
# the deliberate async ILA-snapshot paths (ADC domain -> dbg_* regs on
# clk_120M) suddenly got timed (WNS -8.5ns). The only clk_120M <-> pixel-clock
# paths are the ILA capture and the global reset fanout, both false-pathed
# explicitly, so declaring the Video_clk family its own async group is exact.
# -quiet: tolerate clock names that vanish if the IP config changes.
set_clock_groups -asynchronous \
    -group [get_clocks ADC_dclk_P] \
    -group [get_clocks ADC2_dclk_P] \
    -group [get_clocks -include_generated_clocks SYS_clk] \
    -group [get_clocks -quiet {video_clk0/inst/i_clk_50M clkfbout_Video_clk o_clk_120M_Video_clk o_clk_195M_Video_clk o_clk_65M_Video_clk o_clk_325M_Video_clk}]

############## HDMI output, bank 15 @ 3.3V ####################################
# These pins come from AP_FPGA_TEST/RASBB_AP.xdc (dated 2025-04-20), the
# project HardwareTestResults.md confirms produced "a clean and stable image"
# on real Rev.A silicon - not from this file's own net-tracing of the current
# schematic/PCB source files, which for these particular signals disagreed
# (gave C12/B12, D14/C14, B13/B14, B11/A11 instead). Since the schematic can
# legitimately have moved on since the physical Rev.A boards were fabricated,
# the empirically-verified pins win over the armchair derivation here. N-side
# pins were not in that reference (only P was pinned there); found via the
# FPGA symbol's true differential-pair partner for each P pin.
set_property PACKAGE_PIN A13 [get_ports TMDS_clk_p]
set_property PACKAGE_PIN A14 [get_ports TMDS_clk_n]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_p]
set_property IOSTANDARD TMDS_33 [get_ports TMDS_clk_n]

set_property PACKAGE_PIN B16 [get_ports {TMDS_data_p[0]}]
set_property PACKAGE_PIN B17 [get_ports {TMDS_data_n[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[0]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[0]}]

set_property PACKAGE_PIN A15 [get_ports {TMDS_data_p[1]}]
set_property PACKAGE_PIN A16 [get_ports {TMDS_data_n[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[1]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[1]}]

set_property PACKAGE_PIN B18 [get_ports {TMDS_data_p[2]}]
set_property PACKAGE_PIN A18 [get_ports {TMDS_data_n[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_p[2]}]
set_property IOSTANDARD TMDS_33 [get_ports {TMDS_data_n[2]}]

set_output_delay -clock [get_clocks -include_generated_clocks SYS_clk] -min -add_delay -0.538 [get_ports {TMDS_data_n[*] TMDS_data_p[*] TMDS_clk_n TMDS_clk_p}]
set_output_delay -clock [get_clocks -include_generated_clocks SYS_clk] -max -add_delay 2.538 [get_ports {TMDS_data_n[*] TMDS_data_p[*] TMDS_clk_n TMDS_clk_p}]

############## Asynchronous reset #############################################
# global_rst is a single power-up pulse generated in the clk_120M domain and
# fanned out as an async reset (posedge rst in always blocks) into flip-flops
# in every other clock domain in the design (clk_65M pixel domain, clk_325M
# serial domain, the ADC dclk domain, etc). Its assertion/deassertion is not
# meant to be cycle-accurate with respect to any of those clocks - only that
# it eventually deasserts - so neither the recovery/removal checks on it (when
# synthesis maps it to a FF's dedicated clear/preset pin) nor ordinary
# setup/hold checks (when synthesis instead folds the reset condition into
# fabric logic feeding a D input, e.g. screen.v's "if(i_rst) ... else ..."
# pattern) are meaningful. False-path everything downstream of the register
# that generates it, covering both cases.
set_false_path -to [get_pins -hierarchical -filter {IS_CLEAR || IS_PRESET || IS_RESET}]
set_false_path -from [get_cells -hierarchical -filter {NAME =~ "*global_rst_reg*"}]

# Note: no physical debug pins here anymore. P14/T15 (from AP_FPGA_TEST,
# supposedly a verified-working debug header route) turned out to be
# unconnected on the current Rev.A schematic/PCB - not routed to anything
# probeable. Debug visibility is via an ILA core instead (see run_impl.tcl),
# read over the same JTAG connection used to program the device, so it does
# not depend on knowing which physical header pin is which.

# Some of the ILA-probed nets (video_hs/vs/de) live in the pixel-clock domain
# while the ILA itself samples on clk_120M - a deliberate, purely-for-JTAG-
# readout cross-domain capture, not a functional path. Targeted by clock pair
# rather than by instance/pin name: u_ila_0 is still an unexpanded IP black
# box at the point this constraint first gets evaluated, so a name-pattern
# match only ever reaches its coarse boundary ports (not valid timing
# endpoints), never the real internal capture registers. Clock objects exist
# throughout the flow regardless of IP expansion timing, and this pair is not
# used for any other crossing in the design (nothing crossed between these
# two clocks before the ILA existed), so this exception is exact. The pixel
# clock is found via its MMCM output pin (hdmi_clk.v) since its auto-derived
# name depends on the internal net name.
set_false_path -from [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ "*hdmi_clk0*mmcm_hdmi*CLKOUT1"}]] -to [get_clocks o_clk_120M_Video_clk]
