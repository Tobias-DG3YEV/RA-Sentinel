set repo [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $repo/vivado/RASPMO.runs/impl_1/top_routed.dcp
puts "IO ADC_dclk_P clock region: [get_property CLOCK_REGION [get_sites -of_objects [get_ports i_ADC_dclk_P]]]"
foreach s [lsort -dictionary [get_sites -filter {SITE_TYPE == BUFGCTRL}]] {
    set cr [get_clock_regions -quiet -of_objects [get_sites $s]]
    set used [expr {[llength [get_cells -quiet -of_objects [get_sites $s]]]>0}]
    puts "BUFG $s  region=$cr  used=$used"
}
puts "PROBE2_DONE"
