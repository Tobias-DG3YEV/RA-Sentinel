# RASPMO project creation script.
# Usage: vivado -mode batch -source scripts/create_project.tcl
#
# Builds vivado/RASPMO.xpr from the rtl/ tree at the repo root.
# Target: RASBB's onboard FPGA, XC7A100T-CSG324 speed grade -2.

set repo       [file normalize [file join [file dirname [info script]] ..]]
set proj_name  "RASPMO"
set part       "xc7a100tcsg324-2"

create_project $proj_name "$repo/vivado" -part $part -force

set src_dir    "$repo/rtl/sources"
set sim_dir    "$repo/rtl/sim"
set constr_dir "$repo/rtl/constrs"

# ------------------------------------------------------------------
# RTL sources
# ------------------------------------------------------------------
add_files -fileset sources_1 [glob \
    "$src_dir/*.v" \
    "$src_dir/fft/*.v" \
    "$src_dir/hdmi/*.vhd" \
]

# ------------------------------------------------------------------
# IP: clocking + spectrum/peak-hold memories
# ------------------------------------------------------------------
add_files -fileset sources_1 [glob \
    "$src_dir/ip/Video_clk.xcix" \
    "$src_dir/ip/memory/blk_mem_gen_0.xcix" \
    "$src_dir/ip/memory/blk_PeakMem.xcix" \
]

# ------------------------------------------------------------------
# Simulation sources
# ------------------------------------------------------------------
# The testbenches live in rtl/sim, NOT rtl/sources - run_impl.tcl globs
# rtl/sources/*.v back into the synthesis fileset, so a testbench parked there
# would be pulled in as a design source. They are added to sim_1 only.
add_files -fileset sim_1 [glob -nocomplain "$sim_dir/*.v"]

# ------------------------------------------------------------------
# Constraints
# ------------------------------------------------------------------
add_files -fileset constrs_1 "$constr_dir/RASPMO.xdc"

# ------------------------------------------------------------------
# Top level
# ------------------------------------------------------------------
set_property top top [current_fileset]
update_compile_order -fileset sources_1

# synth_design thread count (see scripts/synth_pre.tcl for the measured
# numbers - it is worth one thread over the default, and 8 is the ceiling).
set_property STEPS.SYNTH_DESIGN.TCL.PRE "$repo/scripts/synth_pre.tcl" [get_runs synth_1]

generate_target all [get_files "$src_dir/ip/Video_clk.xcix"]
generate_target all [get_files "$src_dir/ip/memory/blk_mem_gen_0.xcix"]
generate_target all [get_files "$src_dir/ip/memory/blk_PeakMem.xcix"]

puts "RASPMO project created at $repo/vivado/$proj_name.xpr"
puts "Next: open in the Vivado GUI, or run synthesis/implementation from the Tcl console/batch."
