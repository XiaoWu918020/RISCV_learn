# check_imem_gpo.tcl —— 检查综合后 IMEM 初始化与 GPO 寄存器是否有效
set dcp "C:/Users/19117/Desktop/work/RISC-V/3_stage_pipeline/fpga/RISCV.runs/synth_1/riscv_board.dcp"
open_checkpoint $dcp

puts "INFO: ---- IMEM cells ----"
set imem_cells [get_cells -hier -quiet -filter {NAME =~ *u_imem* && (REF_NAME =~ RAM* || REF_NAME =~ *LUT*)}]
puts "IMEM_CELL_COUNT=[llength $imem_cells]"
set shown 0
foreach c $imem_cells {
    set init ""
    catch {set init [get_property INIT $c]}
    if {$init ne "" && $init ne "256'h0" && $shown < 20} {
        puts "CELL $c REF=[get_property REF_NAME $c] INIT=$init"
        incr shown
    }
}
puts "NONZERO_INIT_SHOWN=$shown"

puts "INFO: ---- GPO registers ----"
foreach c [get_cells -hier -quiet -filter {NAME =~ *gpo*}] {
    set init ""
    catch {set init [get_property INIT $c]}
    puts "CELL $c REF=[get_property REF_NAME $c] INIT=$init"
}

puts "INFO: ---- SoC imem addr nets ----"
foreach n [get_nets -hier -quiet -filter {NAME =~ *u_soc/imem_addr*}] {
    puts "NET [get_property NAME $n] fanout=[llength [get_pins -of_objects $n -quiet]]"
}
close_design
