open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
puts "=== JTAG chain devices ==="
foreach d [get_hw_devices] {
    puts "DEV $d  DONE=[get_property -quiet REGISTER.IR.BYPASS $d] PROGRAM=[get_property -quiet PROGRAM.IS_DONE $d]"
}
foreach d [get_hw_devices] {
    puts "DEVICE $d  is_programmed=[get_property PROGRAM.IS_DONE $d]  cores=[llength [get_hw_ilas -quiet -of_objects $d]]"
}
close_hw_target
disconnect_hw_server
puts "ENUM_DONE"
