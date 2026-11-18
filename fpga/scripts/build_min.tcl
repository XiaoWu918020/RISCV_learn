#==============================================================================
# build_min.tcl —— 用最小裸机固件（min.hex）综合实现，产出独立 bit
# 与 build.tcl 唯一区别：HEX 指向 baremetal_min/build/min.hex，bit 复制为
# riscv_board_min.bit，避免覆盖正式 FreeRTOS 位流。
# Usage: vivado -mode batch -source build_min.tcl
#==============================================================================
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set core_dir   [file dirname $fpga_dir]
set rtl_dir    [file join $core_dir rtl]
set board_dir  [file join $fpga_dir rtl]
set xdc_file   [file join $fpga_dir constrs riscv.xdc]
set hex_file   [file normalize [file join $fpga_dir baremetal_min build min.hex]]
set xpr_file   [file join $fpga_dir RISCV.xpr]

puts "INFO: hex_file = $hex_file"
open_project $xpr_file

# 清理旧引用（幂等）
set old_design [get_files -quiet -of_objects [get_filesets sources_1]]
if { [llength $old_design] > 0 } { remove_files $old_design }
set old_constr [get_files -quiet -of_objects [get_filesets constrs_1]]
if { [llength $old_constr] > 0 } { remove_files $old_constr }

# 核 RTL
set core_files [list \
    riscv_defines.sv riscv_types.svh \
    alu.sv mul.sv div.sv \
    if_unit.sv id_unit.sv rf_unit.sv ex_unit.sv \
    clint.sv riscv_core.sv]
set core_paths [list]
foreach f $core_files { lappend core_paths [file join $rtl_dir $f] }
add_files -norecurse $core_paths

# 板级 RTL + 约束
add_files -norecurse [glob -type f [file join $board_dir *.sv]]
add_files -fileset constrs_1 -norecurse $xdc_file

set_property include_dirs [list $rtl_dir] [get_filesets sources_1]
set_property top riscv_board [get_filesets sources_1]
set_property generic "HEX_FILE=\"$hex_file\"" [get_filesets sources_1]
update_compile_order -fileset sources_1

if { ![file exists $hex_file] } { error "min.hex 不存在：$hex_file" }

# 综合
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] ne "100%" } {
    error "综合失败：[get_property STATUS [get_runs synth_1]]"
}
puts "INFO: 综合完成"

# 实现 + bitstream
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] ne "100%" } {
    error "实现/bitstream 失败：[get_property STATUS [get_runs impl_1]]"
}
puts "INFO: 实现与 bitstream 生成完成"

# 复制为独立文件名，避免与正式 riscv_board.bit 混淆
set src_bit [file join $fpga_dir RISCV.runs impl_1 riscv_board.bit]
set min_bit [file join $fpga_dir RISCV.runs impl_1 riscv_board_min.bit]
file copy -force $src_bit $min_bit
puts "INFO: MIN BITSTREAM = $min_bit"

close_project
puts "INFO: MIN BUILD ALL DONE"
