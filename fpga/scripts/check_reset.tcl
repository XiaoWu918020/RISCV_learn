#==============================================================================
# check_reset.tcl —— 检查板级复位同步器综合结果与 rst_n 扇出
#==============================================================================
set dcp "C:/Users/19117/Desktop/work/RISC-V/3_stage_pipeline/fpga/RISCV.runs/synth_1/riscv_board.dcp"
open_checkpoint $dcp

# 1. 找板级顶层的复位同步寄存器（rst_sync）
puts "INFO: ---- rst_sync FFs ----"
set sync_ff [get_cells -hier -quiet -filter {NAME =~ *rst_sync*}]
foreach ff $sync_ff {
    set ref [get_property REF_NAME $ff]
    puts "CELL $ff REF=$ref"
    foreach pin [get_pins -of_objects $ff] {
        set pname [get_property NAME $pin]
        set net [get_nets -of_objects $pin -quiet]
        set nname ""
        if {$net ne ""} { set nname [get_property NAME [lindex $net 0]] }
        puts "    pin $pname -> $nname"
    }
}

# 2. rst_n 网络扇出到多少个单元
puts "INFO: ---- rst_n net fanout ----"
set rstnet [get_nets -hier -quiet -filter {NAME =~ *rst_n*}]
foreach n $rstnet {
    set pins [get_pins -of_objects $n -quiet]
    puts "NET [get_property NAME $n] fanout_pins=[llength $pins]"
}

# 3. UART tx_ready 寄存器
puts "INFO: ---- uart tx_ready ----"
set tff [get_cells -hier -quiet -filter {NAME =~ *u_uart*tx_ready*}]
foreach ff $tff {
    puts "CELL $ff REF=[get_property REF_NAME $ff] INIT=[get_property INIT $ff]"
}
close_design
