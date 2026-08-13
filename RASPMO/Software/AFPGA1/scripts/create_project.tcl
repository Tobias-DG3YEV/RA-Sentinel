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
# Constraints
# ------------------------------------------------------------------
add_files -fileset constrs_1 "$constr_dir/RASPMO.xdc"

# ------------------------------------------------------------------
# Top level
# ------------------------------------------------------------------
set_property top top [current_fileset]
update_compile_order -fileset sources_1

generate_target all [get_files "$src_dir/ip/Video_clk.xcix"]
generate_target all [get_files "$src_dir/ip/memory/blk_mem_gen_0.xcix"]
generate_target all [get_files "$src_dir/ip/memory/blk_PeakMem.xcix"]

puts "RASPMO project created at $repo/vivado/$proj_name.xpr"
puts "Next: open in the Vivado GUI, or run synthesis/implementation from the Tcl console/batch."
