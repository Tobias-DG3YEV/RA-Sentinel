open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

set dev [lindex [get_hw_devices xc7a100t_0] 0]

puts "REFRESHING..."
refresh_hw_device $dev
puts "REFRESH_DONE"

puts "HW_DEVICES: [get_hw_devices]"
puts "HW_ILAS: [get_hw_ilas -quiet]"

close_hw_target
disconnect_hw_server
puts "SCRIPT_DONE"
