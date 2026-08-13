set repo [file normalize [file join [file dirname [info script]] ..]]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7a100t_0] 0]
current_hw_device $dev
set bit "$repo/vivado/RASPMO.runs/impl_1/top.bit"
set ltx "$repo/vivado/RASPMO.runs/impl_1/top.ltx"
puts "BIT mtime: [clock format [file mtime $bit] -format %H:%M:%S]"
set_property PROGRAM.FILE $bit $dev
set_property PROBES.FILE  $ltx $dev
set_property FULL_PROBES.FILE $ltx $dev
puts "PROGRAMMING $bit"
program_hw_devices $dev
puts "PROGRAM_DONE"
refresh_hw_device $dev
foreach ila [get_hw_ilas] {
    set nm [get_property NAME $ila]
    set pr [lsort [get_property NAME [get_hw_probes -of_objects $ila]]]
    puts "ILA $nm probes: $pr"
}
puts "dbg present? [get_hw_probes -quiet dbg_adc_ipar]"
close_hw_target
disconnect_hw_server
puts "VERIFY_DONE"
