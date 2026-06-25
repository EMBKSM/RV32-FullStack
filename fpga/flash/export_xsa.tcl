set xsa C:/work/github/RV32-FullStack/fpga/flash/rv32_fixed.xsa
puts "=== export fixed hardware platform (with DDR DQS=0.0 fix) ==="
if {[catch {open_project C:/work/github/RV32-FullStack/vivado_zynq/rv32_zynq.xpr} e]} {
    puts "OPEN FAILED (locked? close Vivado GUI): $e"; exit 1
}
if {[file exists $xsa]} { file delete -force $xsa }
# try with bitstream first (uses existing impl_1); fall back to no-bit
if {[catch {write_hw_platform -fixed -include_bit -force $xsa} e1]} {
    puts "include_bit failed: $e1"
    puts "retry without bitstream (FSBL only needs ps7_init)..."
    if {[catch {write_hw_platform -fixed -force $xsa} e2]} {
        puts "no-bit export failed: $e2"
    }
}
puts "XSA exists: [file exists $xsa]"
close_project
puts "=== DONE ==="
