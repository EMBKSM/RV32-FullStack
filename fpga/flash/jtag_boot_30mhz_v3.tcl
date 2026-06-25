# JTAG live-boot 16x16 @ 30.3 MHz, DDR-less, with OCM remapped low (0x0) for the monitor.
connect
source C:/work/github/RV32-FullStack/fpga/flash/ps7_init.tcl
targets -set -nocase -filter {name =~ "*Cortex-A9*#0" || name =~ "*ARM*Cortex-A9*0"}
rst -processor
ps7_mio_init_data_3_0
ps7_pll_init_data_3_0
ps7_clock_init_data_3_0
ps7_peripherals_init_data_3_0
# SLCR: unlock, map all OCM banks LOW (-> OCM at 0x0), FCLK0=30.3MHz, lock
mwr 0xF8000008 0x0000DF0D
mwr 0xF8000910 0x00000000
mwr 0xF8000170 0x00102100
mwr 0xF8000004 0x0000767B
puts "OCM_CFG = [format 0x%08x [lindex [mrd -value 0xF8000910] 0]]"
puts "FCLK0   = [format 0x%08x [lindex [mrd -value 0xF8000170] 0]]"
# probe: try a word write/read at 0x0 to confirm OCM is now there
mwr 0x0 0xCAFEBABE
puts "OCM probe @0x0 = [mrd -value 0x0]"
# configure PL
fpga -f C:/work/github/RV32-FullStack/fpga/flash/rv32_16x16_rtopt_wns-6p74.bit
puts "### 16x16 bitstream programmed ###"
ps7_post_config
# load + run monitor from OCM
dow C:/work/github/RV32-FullStack/rv_ps/rv_firmware/build/rv_firmware.elf
con
after 1000
puts "### MONITOR RUNNING @ OCM 0x0, FCLK0=30.3 MHz, 16x16 NPU ###"
disconnect
puts "JTAG-BOOT-V3-COMPLETE"
