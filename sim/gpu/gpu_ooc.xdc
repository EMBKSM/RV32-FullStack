# OOC timing constraint for the SIMT-lite GPU (target 100 MHz)
create_clock -period 10.000 -name gpu_clk [get_ports clk]
