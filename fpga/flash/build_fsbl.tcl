setws C:/work/github/RV32-FullStack/fpga/flash/ws
puts "=== build FSBL from fixed xsa (DQS=0.0) ==="
if {[catch {app create -name fsbl_fix -hw C:/work/github/RV32-FullStack/fpga/flash/rv32_fixed.xsa -proc ps7_cortexa9_0 -os standalone -template "Zynq FSBL"} e]} {
    puts "APP CREATE ERR: $e"
}
if {[catch {app build -name fsbl_fix} e]} {
    puts "APP BUILD ERR: $e"
}
puts "--- search for fsbl elf ---"
puts [glob -nocomplain C:/work/github/RV32-FullStack/fpga/flash/ws/fsbl_fix/build/*.elf C:/work/github/RV32-FullStack/fpga/flash/ws/fsbl_fix/Debug/*.elf C:/work/github/RV32-FullStack/fpga/flash/ws/*/build/*.elf]
puts "=== DONE ==="
