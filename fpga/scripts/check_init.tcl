#==============================================================================
# check_init.tcl —— 检查综合后 IMEM 分布式 RAM 的 INIT 属性是否真的写入固件
# 用法: vivado -mode batch -source check_init.tcl
#==============================================================================
set dcp "C:/Users/19117/Desktop/work/RISC-V/3_stage_pipeline/fpga/RISCV.runs/synth_1/riscv_board.dcp"
open_checkpoint $dcp

# 列出 IMEM 下所有分布式 RAM 单元
set imem_cells [get_cells -hier -quiet -filter {NAME =~ *u_imem* && REF_NAME == RAM64M8}]
puts "INFO: IMEM RAM64M8 count = [llength $imem_cells]"

# 统计每个 cell 的 INIT 属性是否含非零值
set nonzero_cells 0
set zero_cells 0
foreach c $imem_cells {
    set props [list_property $c]
    set init_props [lsearch -all -inline -regexp $props {^INIT}]
    set has_nz 0
    foreach p $init_props {
        set v [get_property $p $c]
        # 去掉十六进制里的 0 与分隔符后若仍有字符即非零
        set stripped [string map {"0" ""} $v]
        if {$stripped ne ""} { set has_nz 1 }
    }
    if {$has_nz} { incr nonzero_cells } else { incr zero_cells }
}
puts "INFO: IMEM cells with nonzero INIT = $nonzero_cells"
puts "INFO: IMEM cells with all-zero INIT = $zero_cells"

# 打印第一个 cell 的前几个 INIT 属性做人工核对
set first [lindex $imem_cells 0]
if {$first ne ""} {
    puts "INFO: sample cell = $first"
    foreach p [lrange [lsearch -all -inline -regexp [list_property $first] {^INIT}] 0 3] {
        puts "  $p = [get_property $p $first]"
    }
}

# 顺带检查复位信号是否被恒接为有效（找 rst_n 的驱动）
puts "INFO: reset-related pins:"
foreach p [get_pins -hier -quiet -filter {NAME =~ *u_soc*rst_n*}] {
    puts "  pin $p"
}
close_design
