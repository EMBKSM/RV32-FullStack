# rebuild_runtimeopt.tcl - re-run impl_1 with the fast RuntimeOptimized strategy.
# Our 50 MHz timing is trivially met (+8 ns slack), so we skip phys_opt and the
# timing-driven route iterations that made "Implementation Defaults" crawl.
# synth_1 (202 DSP) is already complete and up to date, so this reuses it.
puts "### REBUILD-RUNTIMEOPT ###"
set_param general.maxThreads 8
catch { reset_run impl_1 }
set_property strategy Flow_RuntimeOptimized [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 4
puts "### RELAUNCHED impl_1: Flow_RuntimeOptimized, maxThreads=[get_param general.maxThreads] ###"
