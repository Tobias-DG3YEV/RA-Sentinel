open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

set dev [lindex [get_hw_devices xc7a100t_0] 0]

puts "CURRENT_MASK: [get_property BSCAN_SWITCH_USER_MASK $dev]"
puts "ALL_PROPS:"
foreach p [list_property $dev] {
    if {[string match "*SCAN*" $p] || [string match "*BSCAN*" $p] || [string match "*MASK*" $p]} {
        puts "  $p = [get_property $p $dev]"
    }
}

close_hw_target
disconnect_hw_server
puts "SCRIPT_DONE"
