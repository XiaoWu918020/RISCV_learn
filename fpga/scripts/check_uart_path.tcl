# check_uart_path.tcl —— 打开综合 dcp，检查 UART 读路径/tx_ready/uart 译码
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set dcp        [file join $fpga_dir RISCV.runs synth_1 riscv_board.dcp]
open_checkpoint $dcp

puts "==== 1. 所有 tx_ready 相关寄存器 ===="
foreach c [get_cells -hier -quiet *tx_ready*] {
    puts "CELL: $c  TYPE=[get_property REF_NAME $c]  INIT=[get_property INIT $c]"
}

puts "==== 2. uart 层次下全部 cell（看状态机/读逻辑综合结果） ===="
set uc [get_cells -hier -quiet *u_uart*]
puts "u_uart cell count = [llength $uc]"
foreach c $uc {
    puts "  [get_property REF_NAME $c]  $c"
}

puts "==== 3. tx_ready_reg 的 fanout（数据是否到达读路径） ===="
set tr [get_cells -hier -quiet *tx_ready_reg*]
foreach c $tr {
    set pin [get_pins -quiet -of $c -filter {DIRECTION==OUT}]
    foreach p $pin {
        puts "OUT PIN $p  net=[get_nets -quiet -of $p]"
        set f [get_cells -quiet -of [all_fanout -flat -quiet $p]]
        puts "  fanout cell count=[llength $f]"
        foreach x $f { puts "    -> [get_property REF_NAME $x] $x" }
    }
}

puts "==== CHECK DONE ===="
close_design
