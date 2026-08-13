set repo [file normalize [file join [file dirname [info script]] ..]]
open_checkpoint $repo/vivado/RASPMO.runs/impl_1/top_routed.dcp
puts "dbg_adc_ipar cells: [get_cells -hierarchical -filter {NAME =~ *dbg_adc_ipar*}]"
puts "dbg_adc_ipar nets:  [llength [get_nets -hierarchical -filter {NAME =~ *dbg_adc_ipar*}]]"
foreach dc [get_debug_cores] {
    puts "DEBUGCORE [get_property NAME $dc] ports=[llength [get_debug_ports -of_objects $dc]]"
}
# list probes attached to the ILA that has our video signals
foreach dc [get_debug_cores] {
    set ports [get_debug_ports -of_objects $dc]
    puts "== core [get_property NAME $dc] =="
    foreach p $ports {
        set nets [get_nets -quiet -of_objects $p]
        puts "  [get_property NAME $p] <- [lrange $nets 0 0] (w=[llength $nets])"
    }
}
puts "PROBE_IMPL_DONE"
