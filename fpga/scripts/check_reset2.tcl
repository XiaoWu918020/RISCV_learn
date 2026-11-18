#==============================================================================
# check_reset2.tcl —— 检查重构后 MMCM 上电复位与 rst_n 综合结果
#==============================================================================
set dcp "C:/Users/19117/Desktop/work/RISC-V/3_stage_pipeline/fpga/RISCV.runs/synth_1/riscv_board.dcp"
open_checkpoint $dcp

puts "INFO: ---- reset related cells ----"
set cells [get_cells -hier -quiet -filter {NAME =~ *por* || NAME =~ *rst_sync* || NAME =~ *but_sync* || NAME =~ *mmcm*}]
foreach c $cells {
    set ref [get_property REF_NAME $c]
    set init ""
    catch {set init [get_property INIT $c]}
    puts "CELL $c REF=$ref INIT=$init"
}

puts "INFO: ---- rst_n nets ----"
foreach n [get_nets -hier -quiet -filter {NAME =~ *rst_n*}] {
    set pins [get_pins -of_objects $n -quiet]
    puts "NET [get_property NAME $n] fanout=[llength $pins]"
}

puts "INFO: ---- mmcm locked net ----"
foreach n [get_nets -hier -quiet -filter {NAME =~ *locked*}] {
    set pins [get_pins -of_objects $n -quiet]
    puts "NET [get_property NAME $n] fanout=[llength $pins]"
}

puts "INFO: ---- top MMCM ----"
foreach c [get_cells -hier -quiet -filter {REF_NAME =~ *MMCME*}] {
    puts "MMCM CELL $c REF=[get_property REF_NAME $c]"
    foreach p [get_pins -of_objects $c -filter {NAME =~ *RST* || NAME =~ *LOCKED*}] {
        set nn [get_nets -of_objects $p -quiet]
        puts "  PIN [get_property NAME $p] -> $nn"
    }
}
close_design
