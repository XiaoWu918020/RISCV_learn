# build_uart.tcl —— 用裸机 UART 固件（uart.hex）综合实现，输出独立 bit
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set core_dir   [file dirname $fpga_dir]
set rtl_dir    [file join $core_dir rtl]
set board_dir  [file join $fpga_dir rtl]
set xdc_file   [file join $fpga_dir constrs riscv.xdc]
set hex_file   [file normalize [file join $fpga_dir baremetal_uart build uart.hex]]
set xpr_file   [file join $fpga_dir RISCV.xpr]

puts "INFO: hex_file = $hex_file"
open_project $xpr_file

set old_design [get_files -quiet -of_objects [get_filesets sources_1]]
if { [llength $old_design] > 0 } { remove_files $old_design }
set old_constr [get_files -quiet -of_objects [get_filesets constrs_1]]
if { [llength $old_constr] > 0 } { remove_files $old_constr }

set core_files [list \
    riscv_defines.sv riscv_types.svh \
    alu.sv mul.sv div.sv \
    if_unit.sv id_unit.sv rf_unit.sv ex_unit.sv \
    clint.sv riscv_core.sv]
set core_paths [list]
foreach f $core_files { lappend core_paths [file join $rtl_dir $f] }
add_files -norecurse $core_paths

add_files -norecurse [glob -type f [file join $board_dir *.sv]]
add_files -fileset constrs_1 -norecurse $xdc_file

set_property include_dirs [list $rtl_dir] [get_filesets sources_1]
set_property top riscv_board [get_filesets sources_1]
set_property generic "HEX_FILE=\"$hex_file\"" [get_filesets sources_1]
update_compile_order -fileset sources_1

if { ![file exists $hex_file] } { error "uart.hex 不存在：$hex_file" }

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] ne "100%" } {
    error "综合失败：[get_property STATUS [get_runs synth_1]]"
}
puts "INFO: 综合完成"

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] ne "100%" } {
    error "实现/bitstream 失败：[get_property STATUS [get_runs impl_1]]"
}
puts "INFO: 实现与 bitstream 生成完成"

set src_bit [file join $fpga_dir RISCV.runs impl_1 riscv_board.bit]
set out_bit [file join $fpga_dir RISCV.runs impl_1 riscv_board_uart.bit]
file copy -force $src_bit $out_bit
puts "INFO: UART BITSTREAM = $out_bit"

close_project
puts "INFO: UART BUILD ALL DONE"
