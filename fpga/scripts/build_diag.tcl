#==============================================================================
# File        : build_diag.tcl
# Description : 板级诊断顶层 riscv_board_diag 的综合/实现/bitstream 脚本。
#               诊断设计只例化 IBUFDS/MMCME3_BASE/BUFG 等 Unisim 原语，不依赖
#               核 RTL 与固件，故仅加入诊断文件与 XDC，以获得最快构建。
#   Usage      : vivado -mode batch -source build_diag.tcl
#==============================================================================

# 路径基准
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set board_dir  [file join $fpga_dir rtl]
set xdc_file   [file join $fpga_dir constrs riscv.xdc]
set xpr_file   [file join $fpga_dir RISCV.xpr]

open_project $xpr_file

# 清理旧引用（仅移除工程引用，不删磁盘文件）
set old_design [get_files -quiet -of_objects [get_filesets sources_1]]
if { [llength $old_design] > 0 } {
    remove_files $old_design
}
set old_constr [get_files -quiet -of_objects [get_filesets constrs_1]]
if { [llength $old_constr] > 0 } {
    remove_files $old_constr
}

# 仅加入诊断顶层（其依赖均为 Unisim 原语，工具自动提供）
add_files -norecurse [file join $board_dir riscv_board_diag.sv]
add_files -fileset constrs_1 -norecurse $xdc_file

set_property top riscv_board_diag [get_filesets sources_1]
update_compile_order -fileset sources_1

# 综合
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] ne "100%" } {
    error "诊断综合失败：[get_property STATUS [get_runs synth_1]]"
}
puts "INFO: 诊断综合完成"

# 实现 + bitstream
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] ne "100%" } {
    error "诊断实现/bitstream 失败：[get_property STATUS [get_runs impl_1]]"
}

set bit_file [file join $fpga_dir RISCV.runs impl_1 riscv_board_diag.bit]
puts "INFO: DIAG BITSTREAM = $bit_file"
close_project
puts "INFO: DIAG BUILD DONE"
