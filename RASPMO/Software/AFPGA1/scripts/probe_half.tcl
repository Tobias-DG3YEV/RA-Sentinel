set repo [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $repo/vivado/RASPMO.runs/impl_1/top_routed.dcp
puts "REGIONS: [lsort -dictionary [get_clock_regions]]"
set io [get_sites IOB_X1Y110]
set iotile [get_tiles -of_objects $io]
puts "IO IOB_X1Y110 region=[get_property CLOCK_REGION $io] tileROW=[get_property ROW $iotile]"
# device center row = midpoint of all tile rows
set maxrow 0
foreach t [get_tiles] { set r [get_property ROW $t]; if {$r>$maxrow} {set maxrow $r} }
puts "MAX_TILE_ROW=$maxrow  (center ~= [expr {$maxrow/2}])"
foreach s {BUFGCTRL_X0Y0 BUFGCTRL_X0Y15 BUFGCTRL_X0Y16 BUFGCTRL_X0Y20 BUFGCTRL_X0Y21 BUFGCTRL_X0Y31} {
    set t [get_tiles -quiet -of_objects [get_sites $s]]
    puts "$s tileROW=[get_property -quiet ROW $t]"
}
puts "PROBE_HALF_DONE"
