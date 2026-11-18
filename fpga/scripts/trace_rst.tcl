#==============================================================================
# trace_rst.tcl —— 递归追踪 rst_n 复位树，确认 SoC 内 FF 复位连接与极性
#==============================================================================
set dcp "C:/Users/19117/Desktop/work/RISC-V/3_stage_pipeline/fpga/RISCV.runs/synth_1/riscv_board.dcp"
open_checkpoint $dcp

# 1. 所有名字含 rst 的网络
puts "INFO: ---- nets matching *rst* ----"
foreach n [get_nets -hier -quiet -filter {NAME =~ *rst*}] {
    set pins [get_pins -of_objects $n -quiet]
    puts "NET [get_property NAME $n] pins=[llength $pins]"
}

# 2. 统计全设计中带异步复位(FDCE.CLR / FDPE.PRE)的单元及其网络
puts "INFO: ---- async reset FFs by type ----"
set fdce [get_cells -hier -quiet -filter {REF_NAME == FDCE}]
set fdpe [get_cells -hier -quiet -filter {REF_NAME == FDPE}]
puts "FDCE count = [llength $fdce]"
puts "FDPE count = [llength $fdpe]"

# 3. 追踪 GPO 输出寄存器（驱动 LED）的复位 pin 连接
puts "INFO: ---- GPO reg ----"
set gpo_ff [get_cells -hier -quiet -filter {NAME =~ *gpo* && (REF_NAME == FDCE || REF_NAME == FDPE)}]
foreach ff $gpo_ff {
    puts "CELL $ff REF=[get_property REF_NAME $ff]"
    foreach pin [get_pins -of_objects $ff] {
        set pname [get_property NAME $pin]
        if {$pname -match "C$|CLR|PRE|D$"} {
            set net [get_nets -of_objects $pin -quiet]
            set nn ""
            if {$net ne ""} { set nn [get_property NAME [lindex $net 0]] }
            puts "    $pname -> $nn"
        }
    }
}
close_design
