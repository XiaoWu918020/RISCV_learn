# check_uart2.tcl —— 精确统计 u_uart 层次保留情况及 tx_o 输出
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
open_checkpoint [file join $fpga_dir RISCV.runs synth_1 riscv_board.dcp]

puts "==== 1. filter 精确匹配 u_uart 下全部 cell ===="
set all [get_cells -hier -quiet -filter {NAME =~ *u_uart*}]
puts "u_uart total cell = [llength $all]"
foreach c $all { puts "  [get_property REF_NAME $c]  $c" }

puts "==== 2. 按名字找各预期寄存器 ===="
foreach pat {*u_uart/state* *u_uart/baud* *u_uart/bit* *u_uart/shift* *u_uart/tx_o* *u_uart/tx_ready*} {
    set hit [get_cells -hier -quiet -filter "NAME =~ $pat"]
    puts "$pat : [llength $hit]"
}

puts "==== 3. UART 模块输出 tx_o / 板级 OBUF ===="
foreach c [get_cells -hier -quiet -filter {NAME =~ *uart*tx*}] {
    puts "  [get_property REF_NAME $c] $c"
}
foreach c [get_cells -quiet -filter {REF_NAME == OBUF}] {
    puts "  OBUF $c"
}

puts "==== 4. uart 顶层模块端口引脚 ===="
foreach p [get_pins -hier -quiet -filter {NAME =~ *u_uart/*}] {
    if {[get_pins -quiet -of [get_cells -quiet -filter {NAME =~ *u_uart*}]] eq ""} {}
}
puts "u_uart pins:"
foreach p [get_pins -quiet u_soc/u_uart/*] { puts "  $p DIR=[get_property DIRECTION $p]" }

puts "==== DONE ===="
close_design
