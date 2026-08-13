# Runs as a post-synth_design hook (see run_impl.tcl, which sets this as
# STEPS.SYNTH_DESIGN.TCL.POST on synth_1) on the just-synthesized in-memory
# design, inserting two ILA cores wired to the (* mark_debug = "true" *) nets
# tagged in top.v/lvds_rx.v:
#   u_ila_0, sampled on clk_120M: video/clocking status
#   u_ila_1, sampled on lvds_dclk_buffered (the ADC's own clock domain): the
#     actual ADC/lvds_rx capture pipeline handshake signals
#
# Net matching is by EXACT name (or exact bus base name with an anchored
# "[...]" suffix), not open substring wildcards - a loose "*sig*" pattern
# also catches replicated copies of high-fanout signals (Vivado physically
# duplicates registers with many loads), giving wrong widths and unconnected
# debug-port channels. Where more matches than the expected width still turn
# up (multiple equivalent replicas), only the first `width` are used.
#
# The synth_1 run's checkpoint (top.dcp) is written by Vivado's own
# synth_design sequence BEFORE this hook runs, so anything done here must be
# explicitly re-saved over that same checkpoint at the end.

puts "INSERT_DEBUG: starting"

proc find_net {sig width} {
    if {$width == 1} {
        set m [get_nets -hierarchical -filter "NAME == \"$sig\""]
    } else {
        set m [get_nets -hierarchical -filter "NAME =~ \"${sig}\[*\]\""]
    }
    set n [llength $m]
    if {$n == 0} {
        puts "INSERT_DEBUG: WARNING no net matched for $sig"
        return {}
    }
    if {$n > $width} {
        puts "INSERT_DEBUG: NOTE $sig matched $n nets (expected $width), using first $width"
        set m [lrange $m 0 [expr {$width - 1}]]
    } elseif {$n < $width} {
        puts "INSERT_DEBUG: WARNING $sig matched only $n nets (expected $width)"
    }
    return $m
}

proc add_ila {name clk_net sig_widths {depth 4096}} {
    puts "INSERT_DEBUG: creating $name on $clk_net (depth $depth)"
    create_debug_core $name ila
    set_property C_DATA_DEPTH $depth [get_debug_cores $name]
    set_property C_TRIGIN_EN false [get_debug_cores $name]
    set_property C_TRIGOUT_EN false [get_debug_cores $name]
    set_property C_ADV_TRIGGER false [get_debug_cores $name]
    set_property C_INPUT_PIPE_STAGES 2 [get_debug_cores $name]
    set_property C_EN_STRG_QUAL false [get_debug_cores $name]
    set_property ALL_PROBE_SAME_MU true [get_debug_cores $name]
    set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores $name]

    set_property port_width 1 [get_debug_ports $name/clk]
    connect_debug_port $name/clk [get_nets $clk_net]

    set idx 0
    foreach {sig width} $sig_widths {
        set netref [find_net $sig $width]
        if {[llength $netref] == 0} {
            continue
        }
        if {$idx > 0} {
            create_debug_port $name probe
        }
        set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports $name/probe$idx]
        set_property port_width [llength $netref] [get_debug_ports $name/probe$idx]
        connect_debug_port $name/probe$idx $netref
        puts "INSERT_DEBUG: connected $name/probe$idx -> $sig (width [llength $netref])"
        incr idx
    }
}

add_ila u_ila_0 clk_120M {
    mmcm_locked     1
    global_rst      1
    lvds_fclk       1
    video_hs        1
    video_vs        1
    video_de        1
    spectrumActive  1
    dbg_adc_ipar        12
    dbg_adc_qpar        12
    dbg_chA_expected    12
    dbg_chB_expected    12
    dbg_frameStrobe     1
    dbg_cal_best_tap    5
    dbg_cal_tap         5
    dbg_cal_done        1
}

add_ila u_ila_1 lvds_dclk_buffered {
    lvds_irx0/initSM         2
    lvds_irx0/serdes_rst     1
    lvds_irx0/serdes_CS      1
    lvds_irx0/wordsync       1
    lvds_irx0/bitctr         4
    lvds_irx0/fclk_shifted   1
    adc_frameStrobe          1
    mem_wordWrStrobe         1
    adc_ipar                 12
    adc_qpar                 12
    lvds_irx0/ev12           24
    lvds_irx0/od12           24
    lvds_irx0/anchored       1
    lvds_irx0/reanchor_count 8
    fclk1_cur                12
    fclk2_cur                12
    rot1_cur                 4
    rot2_cur                 4
    rot_change_count         8
    cal_done                 1
    retrain_count1           8
    retrain_count2           8
    fft_result               32
    logfn_result             9
    active_shift             3
    fft_chan                 2
    out_chan                 2
}

# Dedicated core for the ramp-checker BER counters (top.v). These are just
# accumulating counters - we mainly want to read their current value, not a
# deep waveform history, so a much shallower depth is enough and keeps this
# wide (32-bit x4 x2 channels) probe set cheap.
add_ila u_ila_2 lvds_dclk_buffered {
    chA_ramp_expected    12
    chA_ramp_samples     32
    chA_ramp_errors      32
    chA_ramp_biterrors   32
    chA_ramp_locked      1
    chB_ramp_expected    12
    chB_ramp_samples     32
    chB_ramp_errors      32
    chB_ramp_biterrors   32
    chB_ramp_locked      1
} 1024

set_property C_CLK_INPUT_FREQ_HZ 120000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_120M]
puts "INSERT_DEBUG: dbg_hub connected"

write_checkpoint -force top.dcp
puts "INSERT_DEBUG: checkpoint re-saved, done"
