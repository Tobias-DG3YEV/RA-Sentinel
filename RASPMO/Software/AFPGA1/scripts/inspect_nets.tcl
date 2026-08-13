open_checkpoint "[file normalize [file join [file dirname [info script]] ..]]/vivado/RASPMO.runs/synth_1/top.dcp"
puts "=== nets matching chA_ramp_expected ==="
puts [get_nets -hierarchical -filter {NAME =~ "*chA_ramp_expected*"}]
puts "=== nets matching adc_ipar ==="
puts [get_nets -hierarchical -filter {NAME =~ "*adc_ipar*"}]
puts "=== nets matching chA_ramp_samples ==="
puts [get_nets -hierarchical -filter {NAME =~ "*chA_ramp_samples*"}]
