# Close the 106 MHz MMCM build timing (-0.118 ns) via post-route phys_opt.
puts "=== CLOSE_TIMING START ==="
if {[current_design -quiet] eq ""} { puts "OPENING impl_1..."; open_run impl_1 }
puts "DESIGN = [current_design]"
proc _wns {} { return [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]] }
puts "WNS_BEFORE = [_wns]"
phys_opt_design -directive AggressiveExplore
puts "WNS_AFTER_P1 = [_wns]"
phys_opt_design -directive AlternateReplication
puts "WNS_AFTER_P2 = [_wns]"
phys_opt_design -directive AggressiveFanoutOpt
set wns [_wns]
puts "WNS_FINAL = $wns"
report_timing_summary -max_paths 5 -file C:/work/github/RV32-FullStack/flash/timing_mmcm_opt.rpt
if {$wns >= 0.0} {
  write_bitstream -force C:/work/github/RV32-FullStack/flash/rv32_16x16_mmcm_tc.bit
  puts "RESULT: TIMING-CLOSED-106MHZ WNS=$wns  BITSTREAM=rv32_16x16_mmcm_tc.bit"
} else {
  puts "RESULT: STILL-VIOLATED WNS=$wns  (need freq back-off or reroute)"
}
puts "=== CLOSE_TIMING DONE ==="
