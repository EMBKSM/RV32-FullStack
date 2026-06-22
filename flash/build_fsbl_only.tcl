# Rebuild fsbl_fix WITHOUT app create (so the edited ps7_init.c, FCLK0=30.3MHz, is NOT regenerated).
setws C:/work/github/RV32-FullStack/flash/ws
puts "=== rebuild FSBL (app build only, FCLK0 -> 30.3 MHz) ==="
if {[catch {app build -name fsbl_fix} e]} { puts "BUILD ERR: $e" }
puts "ELF: [glob -nocomplain C:/work/github/RV32-FullStack/flash/ws/fsbl_fix/Debug/*.elf C:/work/github/RV32-FullStack/flash/ws/fsbl_fix/build/*.elf]"
puts "=== FSBL-BUILD-DONE ==="
