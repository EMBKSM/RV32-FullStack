## =====================================================================
## zybo_z7_20_pmod.xdc - Pmod headers JA..JE (40 pins) for the RV32 platform
## Pin assignments from the official Digilent Zybo Z7 Rev. B master XDC.
## Top ports come from rv32_top_wrapper (make-external on the BD), so the bus
## names carry the "_0" suffix: ja_io_0[7:0] .. je_io_0[7:0].
##
## Per-header function (matches standard Pmod interface types):
##   JA = SPI0 (Type 2A): [0]SS [1]MOSI [2]MISO [3]SCLK ; [4..7] GPIO0..3
##   JB = SPI1          : [0]SS [1]MOSI [2]MISO [3]SCLK ; [4..7] GPIO4..7
##   JC = I2C0 (Type 6A): [2]SCL [3]SDA ; [0,1,4..7] GPIO8..13
##   JD = I2C1          : [2]SCL [3]SDA ; [0,1,4..7] GPIO14..19
##   JE = UART+PWM      : [1]TXD [2]RXD ; [4..7] PWM0..3 ; [0,3] GPIO20..21
## If a real I2C Pmod with its own pull-ups is attached the internal PULLUPs are
## harmless; they let the bus idle high for bench testing without a module.
## =====================================================================

## ---- Pmod JA (SPI0 + GPIO) ----
set_property -dict { PACKAGE_PIN N15 IOSTANDARD LVCMOS33 } [get_ports {ja_io_0[0]}]
set_property -dict { PACKAGE_PIN L14 IOSTANDARD LVCMOS33 } [get_ports {ja_io_0[1]}]
set_property -dict { PACKAGE_PIN K16 IOSTANDARD LVCMOS33 } [get_ports {ja_io_0[2]}]
set_property -dict { PACKAGE_PIN K14 IOSTANDARD LVCMOS33 } [get_ports {ja_io_0[3]}]
set_property -dict { PACKAGE_PIN N16 IOSTANDARD LVCMOS33 } [get_ports {ja_io_0[4]}]
set_property -dict { PACKAGE_PIN L15 IOSTANDARD LVCMOS33 } [get_ports {ja_io_0[5]}]
set_property -dict { PACKAGE_PIN J16 IOSTANDARD LVCMOS33 } [get_ports {ja_io_0[6]}]
set_property -dict { PACKAGE_PIN J14 IOSTANDARD LVCMOS33 } [get_ports {ja_io_0[7]}]

## ---- Pmod JB (SPI1 + GPIO) ----
set_property -dict { PACKAGE_PIN V8  IOSTANDARD LVCMOS33 } [get_ports {jb_io_0[0]}]
set_property -dict { PACKAGE_PIN W8  IOSTANDARD LVCMOS33 } [get_ports {jb_io_0[1]}]
set_property -dict { PACKAGE_PIN U7  IOSTANDARD LVCMOS33 } [get_ports {jb_io_0[2]}]
set_property -dict { PACKAGE_PIN V7  IOSTANDARD LVCMOS33 } [get_ports {jb_io_0[3]}]
set_property -dict { PACKAGE_PIN Y7  IOSTANDARD LVCMOS33 } [get_ports {jb_io_0[4]}]
set_property -dict { PACKAGE_PIN Y6  IOSTANDARD LVCMOS33 } [get_ports {jb_io_0[5]}]
set_property -dict { PACKAGE_PIN V6  IOSTANDARD LVCMOS33 } [get_ports {jb_io_0[6]}]
set_property -dict { PACKAGE_PIN W6  IOSTANDARD LVCMOS33 } [get_ports {jb_io_0[7]}]

## ---- Pmod JC (I2C0 on [2]=SCL/[3]=SDA + GPIO) ----
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports {jc_io_0[0]}]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS33 } [get_ports {jc_io_0[1]}]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 PULLUP true } [get_ports {jc_io_0[2]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 PULLUP true } [get_ports {jc_io_0[3]}]
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {jc_io_0[4]}]
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports {jc_io_0[5]}]
set_property -dict { PACKAGE_PIN T12 IOSTANDARD LVCMOS33 } [get_ports {jc_io_0[6]}]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {jc_io_0[7]}]

## ---- Pmod JD (I2C1 on [2]=SCL/[3]=SDA + GPIO) ----
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports {jd_io_0[0]}]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports {jd_io_0[1]}]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 PULLUP true } [get_ports {jd_io_0[2]}]
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 PULLUP true } [get_ports {jd_io_0[3]}]
set_property -dict { PACKAGE_PIN U14 IOSTANDARD LVCMOS33 } [get_ports {jd_io_0[4]}]
set_property -dict { PACKAGE_PIN U15 IOSTANDARD LVCMOS33 } [get_ports {jd_io_0[5]}]
set_property -dict { PACKAGE_PIN V17 IOSTANDARD LVCMOS33 } [get_ports {jd_io_0[6]}]
set_property -dict { PACKAGE_PIN V18 IOSTANDARD LVCMOS33 } [get_ports {jd_io_0[7]}]

## ---- Pmod JE (UART [1]TXD/[2]RXD + PWM [4..7] + GPIO [0,3]) ----
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {je_io_0[0]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports {je_io_0[1]}]
set_property -dict { PACKAGE_PIN J15 IOSTANDARD LVCMOS33 } [get_ports {je_io_0[2]}]
set_property -dict { PACKAGE_PIN H15 IOSTANDARD LVCMOS33 } [get_ports {je_io_0[3]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {je_io_0[4]}]
set_property -dict { PACKAGE_PIN U17 IOSTANDARD LVCMOS33 } [get_ports {je_io_0[5]}]
set_property -dict { PACKAGE_PIN T17 IOSTANDARD LVCMOS33 } [get_ports {je_io_0[6]}]
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports {je_io_0[7]}]
