# flash_board.tcl - programming logic used by flash_board.sh
# Reads the bit file path from env var BIT_FILE.
set bit [file normalize $env(BIT_FILE)]
puts "BIT_FILE = $bit"
if {![file exists $bit]} {
  puts "ERROR: bit file not found: $bit"
  exit 1
}
open_hw_manager
connect_hw_server
set targets [get_hw_targets -quiet]
if {[llength $targets] == 0} {
  puts "ERROR: no JTAG target found (check cable / board power)"
  close_hw_manager
  exit 2
}
current_hw_target [lindex $targets 0]
open_hw_target
set devs [get_hw_devices]
if {[llength $devs] == 0} {
  puts "ERROR: no device found on target"
  close_hw_manager
  exit 2
}
set dev [lindex $devs 0]
puts "=== FOUND DEVICE: $dev ==="
current_hw_device $dev
refresh_hw_device -update_hw_probes false [current_hw_device]
set_property PROGRAM.FILE $bit [current_hw_device]
program_hw_devices [current_hw_device]
puts "=== PROGRAM DONE ==="
close_hw_manager
exit 0
