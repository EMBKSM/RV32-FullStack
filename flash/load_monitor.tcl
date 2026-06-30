# Program the unified bitstream, then download + run the ARM PS monitor
# (rv_firmware.elf) on Cortex-A9. The monitor talks to the host GUI over the
# PS-UART (board USB COM) and drives the RV32 via AXI-Lite @0x4000_0000.
# After this the GUI (rv32_gui.py) can connect over the COM port for LIVE control.
connect
source C:/work/github/RV32-FullStack/flash/ps7_init.tcl
targets -set -nocase -filter {name =~ "*Cortex-A9*#0" || name =~ "*ARM*Cortex-A9*0"}
configparams force-mem-access 1
rst -processor
ps7_mio_init_data_3_0
ps7_pll_init_data_3_0
ps7_clock_init_data_3_0
ps7_peripherals_init_data_3_0
mwr 0xF8000008 0x0000DF0D
mwr 0xF8000170 0x00100A00
mwr 0xF8000004 0x0000767B
fpga -f C:/work/github/RV32-FullStack/fpga/flash/rv32_unified_100mhz.bit
ps7_post_config
puts "### FPGA programmed (unified, 202 DSP). Downloading ARM monitor... ###"
dow C:/work/github/RV32-FullStack/rv_ps/rv_firmware/build/rv_firmware.elf
puts "### monitor downloaded to Cortex-A9; starting ... ###"
con
after 1500
puts "### ARM monitor running (UART 115200). Disconnecting JTAG; monitor keeps running. ###"
disconnect
puts "MONITOR-RUNNING"
