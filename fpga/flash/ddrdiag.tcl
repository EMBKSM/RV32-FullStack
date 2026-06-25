# DDR byte-lane test - NO reset/init. Tests whatever DDR state currently exists
# (relies on DDR already being initialized by a Vitis run / FSBL).
proc hx {s} { regsub -nocase {^0x} $s "" s; scan $s %x v; return [expr {$v & 0xFFFFFFFF}] }
puts "=== DDR byte-lane test (no reset - current state) ==="
if {[catch {connect} e]} { puts "CONNECT FAIL: $e"; exit }
catch { targets -set -filter {name =~ "*Cortex-A9*#1"} }
puts "target selected (no reset/init performed)"

puts "\n--- byte-lane isolation ---"
proc t1 {addr val} {
    mwr $addr $val
    set r [hx [lindex [mrd -value $addr 1] 0]]
    puts [format "  @%08X w=%08X r=%08X %s" $addr $val $r [expr {$r==$val?"OK":"MISMATCH"}]]
}
t1 0x00200000 0xFF000000
t1 0x00200004 0x00FF0000
t1 0x00200008 0x0000FF00
t1 0x0020000C 0x000000FF
t1 0x00200010 0xFFFFFFFF
t1 0x00200020 0x12345678
t1 0x00200024 0xAA55AA55
t1 0x00200028 0xDEADBEEF

puts "\n--- bulk 1024 x3, byte-lane tally ---"
array set lane {0 0 1 0 2 0 3 0}; set total 0; set errs 0
foreach base {0x00400000 0x04000000 0x10000000} {
    set N 1024; set data {}
    for {set i 0} {$i<$N} {incr i} { lappend data [format 0x%08X [expr {((($i+1)*2654435761)^($i<<11)^$base)&0xFFFFFFFF}]] }
    mwr $base $data
    set rd [mrd -value $base $N]
    for {set i 0} {$i<$N} {incr i} {
        incr total
        set ev [hx [lindex $data $i]]; set gv [hx [lindex $rd $i]]
        if {$ev!=$gv} { incr errs; set x [expr {$ev^$gv}]; for {set b 0} {$b<4} {incr b} { if {(($x>>($b*8))&0xFF)!=0} {incr lane($b)} } }
    }
}
puts "  words=$total errors=$errs  byte0=$lane(0) byte1=$lane(1) byte2=$lane(2) byte3=$lane(3)"
puts "  (lower 3 OK + byte3 high => byte-lane 3 fault confirmed)"
puts "=== END ==="
catch { disconnect }
