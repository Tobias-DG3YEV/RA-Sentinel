# One-shot ILA capture for BER diagnosis. Wraps each core in catch so a core
# on a stopped clock doesn't abort the run, and writes the object returned by
# upload_hw_ila_data (not current_hw_ila_data, which can be a stale handle).
set repo [file normalize [file join [file dirname [info script]] ..]]
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target
set dev [lindex [get_hw_devices xc7a100t_0] 0]
current_hw_device $dev
set ltx "$repo/vivado/RASPMO.runs/impl_1/top.ltx"
set_property PROBES.FILE $ltx $dev
set_property FULL_PROBES.FILE $ltx $dev
refresh_hw_device $dev

set outdir "$repo/ila_out"
file mkdir $outdir

foreach ila [get_hw_ilas] {
    set name [get_property NAME $ila]
    # tag each core by a signature probe so the CSV name says what it holds
    set probes [get_property NAME [get_hw_probes -of_objects $ila]]
    set tag $name
    if {[lsearch $probes "lvds_fclk"] >= 0}      { set tag "u_ila_0_video" }
    if {[lsearch $probes "adc_ipar"] >= 0}       { set tag "u_ila_1_capture" }
    if {[lsearch $probes "chA_ramp_samples"] >= 0} { set tag "u_ila_2_counters" }
    puts "CORE $name -> $tag"
    if {[catch {
        reset_hw_ila $ila
        run_hw_ila -trigger_now $ila
        wait_on_hw_ila $ila
        set d [upload_hw_ila_data $ila]
        write_hw_ila_data -csv_file "$outdir/$tag.csv" -force $d
        puts "WROTE $outdir/$tag.csv"
    } err]} {
        puts "CORE_FAIL $tag : $err"
    }
}

close_hw_target
disconnect_hw_server
puts "CAPTURE_DONE"
