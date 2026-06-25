# Cleanly configure the 16x16 NPU bitstream on the board @ 30.3 MHz (no monitor/OCM/DDR).
connect
source C:/work/github/RV32-FullStack/fpga/flash/ps7_init.tcl
targets -set -nocase -filter {name =~ "*Cortex-A9*#0" || name =~ "*ARM*Cortex-A9*0"}
rst -processor
ps7_mio_init_data_3_0
ps7_pll_init_data_3_0
ps7_clock_init_data_3_0
ps7_peripherals_init_data_3_0
mwr 0xF8000008 0x0000DF0D
mwr 0xF8000170 0x00102100
mwr 0xF8000004 0x0000767B
fpga -f C:/work/github/RV32-FullStack/fpga/flash/rv32_16x16_rtopt_wns-6p74.bit
ps7_post_config
puts "FCLK0 = [format 0x%08x [lindex [mrd -value 0xF8000170] 0]]  -> 30.3 MHz"
puts "### 16x16 NPU CONFIGURED + CLOCKED ON BOARD @ 30.3 MHz (DONE asserted) ###"
disconnect
puts "PROGRAM-ONLY-COMPLETE"
