set repo [file normalize [file join [file dirname [info script]] ..]]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

set dev [lindex [get_hw_devices xc7a100t_0] 0]
set_property PROGRAM.FILE "$repo/vivado/RASPMO.runs/impl_1/top.bit" $dev
# probes file only exists when the build inserted ILAs (see run_impl.tcl)
set ltx "$repo/vivado/RASPMO.runs/impl_1/top.ltx"
if {[file exists $ltx]} {
    set_property PROBES.FILE $ltx $dev
    set_property FULL_PROBES.FILE $ltx $dev
} else {
    set_property PROBES.FILE {} $dev
    set_property FULL_PROBES.FILE {} $dev
}

puts "PROGRAMMING..."
program_hw_devices $dev
puts "PROGRAM_DONE"

refresh_hw_device $dev
puts "HW_ILAS: [get_hw_ilas -quiet]"

close_hw_target
disconnect_hw_server
puts "SCRIPT_DONE"
