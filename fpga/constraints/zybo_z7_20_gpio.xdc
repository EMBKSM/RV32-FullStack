## =====================================================================
## zybo_z7_20_gpio.xdc - LED / Switch / Button pin constraints (Zybo Z7-20)
## System clock + UART come from the Zynq PS (FCLK / MIO), so only PL GPIO is
## constrained here. Top ports (from rv32_top_wrapper): led_o_0 / sw_i_0 / btn_i_0.
## =====================================================================

## ---- LEDs LD0..LD3 ----
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports {led_o_0[0]}]
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports {led_o_0[1]}]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports {led_o_0[2]}]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports {led_o_0[3]}]

## ---- Switches SW0..SW3 ----
set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports {sw_i_0[0]}]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports {sw_i_0[1]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {sw_i_0[2]}]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports {sw_i_0[3]}]

## ---- Buttons BTN0..BTN3 ----
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports {btn_i_0[0]}]
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS33 } [get_ports {btn_i_0[1]}]
set_property -dict { PACKAGE_PIN K19 IOSTANDARD LVCMOS33 } [get_ports {btn_i_0[2]}]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports {btn_i_0[3]}]
