# Reopen the routed checkpoint and break down WHERE the 100MHz failing paths are.
open_checkpoint C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.runs/impl_1/rv32_top_wrapper_routed.dcp
puts "### WNS = [get_property SLACK [lindex [get_timing_paths -max_paths 1 -nworst 1 -setup] 0]] ###"
# worst 40 setup paths, one-line summaries (shows startpoint->endpoint hierarchy)
set paths [get_timing_paths -max_paths 40 -nworst 40 -setup]
set i 0
foreach p $paths {
    set slk [get_property SLACK $p]
    set sp  [get_property STARTPOINT_PIN $p]
    set ep  [get_property ENDPOINT_PIN $p]
    puts [format "P%02d  slack=%6.3f  %s  ->  %s" $i $slk $sp $ep]
    incr i
}
# bucket failing endpoints by coarse hierarchy
puts "### endpoint buckets (failing setup) ###"
set fp [get_timing_paths -max_paths 4000 -nworst 1 -setup -slack_less_than 0]
array set cnt {core 0 npu 0 axi 0 cache 0 other 0}
foreach p $fp {
    set ep [get_property ENDPOINT_PIN $p]
    if {[string match *u_core* $ep] && [string match *cache* $ep]==0} { incr cnt(core) } \
    elseif {[string match *u_npu* $ep]} { incr cnt(npu) } \
    elseif {[string match *cache* $ep] || [string match *cache* $ep]} { incr cnt(cache) } \
    elseif {[string match *axi_smc* $ep] || [string match *axi* $ep]} { incr cnt(axi) } \
    else { incr cnt(other) }
}
puts "core=$cnt(core)  npu=$cnt(npu)  cache=$cnt(cache)  axi=$cnt(axi)  other=$cnt(other)"
puts "### ANALYZE-DONE ###"
