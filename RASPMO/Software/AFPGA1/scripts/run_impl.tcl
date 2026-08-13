# Runs synthesis + implementation (through bitstream) for RASPMO and reports
# timing/utilization summaries at the end.
# Usage: vivado -mode batch -source scripts/run_impl.tcl

set repo      [file normalize [file join [file dirname [info script]] ..]]
set proj_path "$repo/vivado/RASPMO.xpr"

if {![file exists $proj_path]} {
    puts "ERROR: $proj_path does not exist - run create_project.tcl first."
    exit 1
}

open_project $proj_path

# Defensively (re-)add every RTL source in rtl/sources - a Vivado GUI session
# holding an older in-memory project state can rewrite the .xpr on save and
# silently drop files that were added on disk since (this happened with
# waterfall_mem.v -> "module not found"). add_files skips already-present
# files, so this is idempotent and cheap.
foreach f [glob -nocomplain "$repo/rtl/sources/*.v"] {
    if {[llength [get_files -quiet [file tail $f]]] == 0} {
        puts "RUN_IMPL: re-adding missing source $f"
        add_files -fileset sources_1 $f
    }
}

# ...and the inverse: drop project references whose file no longer exists on
# disk (a source deleted/renamed on disk otherwise breaks synthesis with
# "module not found"-style errors, as lvds_rx.v once did). ONLY plain .v files
# directly in rtl/sources are considered: IP / core-container members report
# virtual extracted paths that legitimately fail [file exists], and calling
# remove_files on one of those crashes Vivado outright (observed segfault).
set rtl_dir [file normalize "$repo/rtl/sources"]
foreach f [get_files -quiet -of_objects [get_filesets sources_1]] {
    set fn [file normalize $f]
    if {[file dirname $fn] ne $rtl_dir} { continue }
    if {[file extension $fn] ne ".v"} { continue }
    if {![file exists $fn]} {
        puts "RUN_IMPL: removing stale source reference $fn"
        remove_files -fileset sources_1 $fn
    }
}

# ILA insertion disabled after the LVDS framing fix was verified (2026-07-24)
# - the debug cores cost BRAM/LUTs and add JTAG/BSCAN logic for nothing in
# normal operation. To debug again, re-enable the post-synth hook:
#set_property STEPS.SYNTH_DESIGN.TCL.POST "$repo/scripts/insert_debug.tcl" [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.TCL.POST "" [get_runs synth_1]

reset_run synth_1
launch_runs synth_1 -jobs 16
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "SYNTH_FAILED"
    exit 1
}
puts "SYNTH_OK"

# NOTE: do NOT enable STEPS.POST_ROUTE_PHYS_OPT_DESIGN here. It was tried to
# close a -0.004ns violation on the ADC-domain negedge waterfall write path and
# left ADC_dclk_P unrouted ("DRC RTSTAT-1: 1 net(s) are unrouted"), which kills
# write_bitstream outright. Not worth it for picoseconds.
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED false [get_runs impl_1]

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 16
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "IMPL_FAILED"
    exit 1
}
puts "IMPL_OK"

open_run impl_1
set outdir "$repo/vivado/reports"
file mkdir $outdir
report_timing_summary -file "$outdir/timing_summary.rpt"
report_utilization -file "$outdir/utilization.rpt"
report_clock_interaction -file "$outdir/clock_interaction.rpt"

puts "DONE"
