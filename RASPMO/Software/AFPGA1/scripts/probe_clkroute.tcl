# Investigate the DCLK IO->BUFG clock route in the implemented design so we can
# choose a deterministic BUFGCTRL LOC for BUFG_lvds_dclk_1.
set repo [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $repo/vivado/RASPMO.runs/impl_1/top_routed.dcp

puts "==== ADC_dclk_P port / IOB ===="
set p [get_ports i_ADC_dclk_P]
puts "PORT ADC_dclk_P  PACKAGE_PIN=[get_property PACKAGE_PIN $p]"
set iob [get_sites -of_objects [get_ports i_ADC_dclk_P]]
puts "IOB site=$iob  CLOCK_REGION=[get_property CLOCK_REGION $iob]"

puts "==== IBUFDS placement ===="
set ibuf [get_cells -hierarchical -filter {NAME =~ *IBUFDS_adc_dclk}]
puts "IBUFDS cell=$ibuf site=[get_property LOC $ibuf] [get_property SITE $ibuf]"

puts "==== BUFG_lvds_dclk_1 current placement ===="
set bufg [get_cells -hierarchical -filter {NAME =~ *BUFG_lvds_dclk_1}]
set bsite [get_property SITE $bufg]
puts "BUFG cell=$bufg SITE=$bsite CLOCK_REGION=[get_property CLOCK_REGION [get_sites $bsite]]"

puts "==== All BUFGCTRL sites + clock region ===="
foreach s [lsort [get_sites -filter {SITE_TYPE == BUFGCTRL}]] {
    puts "  $s  CR=[get_property CLOCK_REGION $s]  used?=[expr {[llength [get_cells -quiet -of_objects [get_sites $s]]]>0}]"
}

puts "==== route delay of the IO->BUFG net (lvds_dclk) ===="
set net [get_nets -hierarchical -filter {NAME =~ *IBUFDS_adc_dclk/i} ]
puts "checking parent net of IBUFDS output -> BUFG.I"
report_property [get_nets -hierarchical -filter {NAME =~ *o_lvds_dclk* || NAME =~ *lvds_dclk}] -quiet
puts "PROBE_DONE"
