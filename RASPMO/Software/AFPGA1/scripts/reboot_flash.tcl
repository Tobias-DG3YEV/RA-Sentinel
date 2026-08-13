open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7a100t_0] 0]
current_hw_device $dev
boot_hw_device $dev
puts "REBOOTED"
close_hw_target
disconnect_hw_server
