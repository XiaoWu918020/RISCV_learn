# check_uart3.tcl —— 追踪 tx_ready 到核 load 数据输入的完整组合路径
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
open_checkpoint [file join $fpga_dir RISCV.runs synth_1 riscv_board.dcp]

puts "==== A. uart 读 mux：u_uart 内所有 LUT 及其输入/输出 net ===="
foreach lc [get_cells -hier -quiet -filter {NAME =~ *u_uart* && REF_NAME =~ LUT*}] {
    puts "LUT $lc INIT=[get_property INIT $lc]"
    foreach p [get_pins -quiet -of $lc] {
        set d [get_property DIRECTION $p]
        set n [get_nets -quiet -of $p]
        puts "    $d $p  net=$n"
    }
}

puts "==== B. SoC 读 mux 相关：u_soc 下连到 dmem_rdata 的 cell ===="
foreach p [get_pins -hier -quiet -filter {NAME =~ *dmem_rdata*}] {
    set n [get_nets -quiet -of $p]
    puts "PIN $p DIR=[get_property DIRECTION $p] net=$n"
}

puts "==== C. uart_sel / 地址译码信号 ===="
foreach n [get_nets -hier -quiet -filter {NAME =~ *uart_sel*}] {
    puts "NET $n"
    foreach p [get_pins -quiet -of $n] { puts "    [get_property DIRECTION $p] $p" }
}

puts "==== DONE ===="
close_design
