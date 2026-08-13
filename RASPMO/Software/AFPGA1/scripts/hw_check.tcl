set repo [file normalize [file join [file dirname [info script]] ..]]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

set dev [lindex [get_hw_devices xc7a100t_0] 0]
set_property PROGRAM.FILE "$repo/vivado/RASPMO.runs/impl_1/top.bit" $dev
set_property PROBES.FILE "$repo/vivado/RASPMO.runs/impl_1/top.ltx" $dev
set_property FULL_PROBES.FILE "$repo/vivado/RASPMO.runs/impl_1/top.ltx" $dev

puts "PROGRAMMING..."
program_hw_devices $dev
puts "PROGRAM_DONE"

puts "TRYING BSCAN MASK FIX..."
set_property BSCAN_SWITCH_USER_MASK 2 $dev
refresh_hw_device $dev
puts "REFRESH_DONE"

puts "HW_DEVICES:"
puts [get_hw_devices]

puts "DEBUG_CORES:"
catch {puts [get_hw_ilas]} res
puts "ILA_QUERY_RESULT: $res"

close_hw_target
disconnect_hw_server
puts "SCRIPT_DONE"
