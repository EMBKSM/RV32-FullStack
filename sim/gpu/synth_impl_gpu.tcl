set R C:/work/github/RV32-FullStack
read_vhdl -vhdl2008 [list \
  $R/rtl/gpu/gpu_pkg.vhd $R/rtl/gpu/gpu_lane.vhd \
  $R/rtl/gpu/gpu_core.vhd $R/rtl/gpu/gpu_top.vhd]
read_xdc $R/sim/gpu/gpu_ooc.xdc
synth_design -mode out_of_context -top gpu_top -part xc7z020clg400-1 -retiming
opt_design
place_design -directive Explore
route_design -directive Explore
report_utilization    -file $R/_gpu_util.rpt
# --- post-route timing is written first so a report always exists even if
#     phys_opt later misbehaves (AggressiveExplore crashed the tool before) ---
report_timing_summary -file $R/_gpu_timing.rpt -max_paths 5
puts "================  GPU OOC TIMING (post-route)  ================"
puts [report_timing_summary -return_string -no_detailed_paths]
# --- default (stable) phys_opt; overwrite the report if it completes ---
if {[catch {phys_opt_design} pe]} {
    puts "phys_opt_design raised: $pe (keeping post-route report)"
} else {
    report_timing_summary -file $R/_gpu_timing.rpt -max_paths 5
    puts "================  GPU OOC TIMING (post phys_opt)  ================"
    puts [report_timing_summary -return_string -no_detailed_paths]
}
