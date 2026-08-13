# Indirect-program the RASPMO (dbg) bitstream into FPGA1's S25FL128L config
# flash (IC5) through the FPGA over JTAG, then boot the FPGA from flash.
# The TS3A5018 mux (IC6) defaults (POR pull-downs) to flash<->FPGA1, so the
# flash-programmer bridge Vivado loads into FPGA1 can reach IC5.
set repo [file normalize [file join [file dirname [info script]] ..]]
set base $repo/vivado/RASPMO.runs/impl_1
set bit  $base/top.bit
set mcs  $repo/top.mcs

# 1) wrap the .bit into a flash image (SPI x1, 128 Mbit = 16 MByte)
write_cfgmem -format mcs -interface SPIx1 -size 16 \
    -loadbit "up 0x00000000 $bit" -file $mcs -force
puts "MCS_WRITTEN $mcs"

# 2) connect and indirect-program the flash
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7a100t_0] 0]
current_hw_device $dev
refresh_hw_device -update_hw_probes false $dev

create_hw_cfgmem -hw_device $dev [lindex [get_cfgmem_parts {s25fl128l-spi-x1_x2_x4}] 0]
set cfgmem [get_property PROGRAM.HW_CFGMEM $dev]
set_property PROGRAM.FILES [list $mcs] $cfgmem
set_property PROGRAM.ADDRESS_RANGE {use_file} $cfgmem
set_property PROGRAM.BLANK_CHECK 0 $cfgmem
set_property PROGRAM.ERASE 1 $cfgmem
set_property PROGRAM.CFG_PROGRAM 1 $cfgmem
set_property PROGRAM.VERIFY 1 $cfgmem
set_property PROGRAM.CHECKSUM 0 $cfgmem

# load the Xilinx flash-programmer bridge design into the FPGA
create_hw_bitstream -hw_device $dev [get_property PROGRAM.HW_CFGMEM_BITFILE $dev]
program_hw_devices $dev
refresh_hw_device $dev

puts "FLASH_PROGRAMMING..."
program_hw_cfgmem -hw_cfgmem $cfgmem
puts "FLASH_PROGRAM_DONE"

# 3) boot the FPGA from flash (JPROGRAM -> master-SPI reconfig)
boot_hw_device $dev
puts "BOOTED_FROM_FLASH"

close_hw_target
disconnect_hw_server
puts "PROGRAM_FLASH_DONE"
