# JTAG live-boot 16x16 @ 30.3 MHz, DDR-less (monitor runs from OCM @ 0x0).
# Run PS init WITHOUT ps7_ddr_init so OCM stays mapped at 0x0.
connect
source C:/work/github/RV32-FullStack/fpga/flash/ps7_init.tcl
targets -set -nocase -filter {name =~ "*Cortex-A9*#0" || name =~ "*ARM*Cortex-A9*0"}
rst -processor
# --- PS init minus DDR (silicon 3.0) ---
ps7_mio_init_data_3_0
ps7_pll_init_data_3_0
ps7_clock_init_data_3_0
ps7_peripherals_init_data_3_0
# --- FCLK0 -> 30.3 MHz (FPGA0_CLK_CTRL divisor 33) ---
mwr 0xF8000008 0xDF0D
mwr 0xF8000170 0x00102100
mwr 0xF8000004 0x767B
puts "FCLK0_CLK_CTRL = [format 0x%08x [lindex [mrd -value 0xF8000170] 0]]   -> 30.3 MHz"
# --- configure PL with 16x16 bitstream ---
fpga -f C:/work/github/RV32-FullStack/fpga/flash/rv32_16x16_rtopt_wns-6p74.bit
puts "### 16x16 bitstream programmed ###"
ps7_post_config
# --- load monitor to OCM 0x0 and verify, then run ---
dow C:/work/github/RV32-FullStack/rv_ps/rv_firmware/build/rv_firmware.elf
puts "OCM@0x0 after dow = [mrd 0x0 4]"
con
after 1000
puts "### MONITOR RUNNING (OCM, no DDR, FCLK0=30.3 MHz, 16x16 NPU) ###"
disconnect
puts "JTAG-BOOT-V2-COMPLETE"
