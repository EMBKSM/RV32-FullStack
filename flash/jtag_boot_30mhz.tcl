# JTAG live-boot of the 16x16 NPU @ 30.3 MHz (no QSPI, no DDR -- monitor runs from OCM).
connect
source C:/work/github/RV32-FullStack/flash/ps7_init.tcl
puts "=== targets ==="; targets
targets -set -nocase -filter {name =~ "*Cortex-A9*#0" || name =~ "*ARM*Cortex-A9*0"}
rst -processor
ps7_init
# override FCLK0 -> 30.3 MHz (FPGA0_CLK_CTRL divisor 33) BEFORE the PL runs
mwr 0xF8000008 0xDF0D
mwr 0xF8000170 0x00102100
mwr 0xF8000004 0x767B
puts "FCLK0_CLK_CTRL = [format 0x%08x [lindex [mrd -value 0xF8000170] 0]]   (0x00102100 -> 30.3 MHz)"
# configure the PL with the 16x16 bitstream
fpga -f C:/work/github/RV32-FullStack/flash/rv32_16x16_rtopt_wns-6p74.bit
puts "### 16x16 bitstream programmed ###"
ps7_post_config
# load the PS monitor into OCM (0x0) and run it
dow C:/work/github/RV32-FullStack/rv_ps/rv_firmware/build/rv_firmware.elf
con
after 800
puts "### MONITOR RUNNING @ OCM, FCLK0=30.3 MHz, 16x16 NPU on PL ###"
disconnect
puts "JTAG-BOOT-COMPLETE"
