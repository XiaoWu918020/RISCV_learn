#==============================================================================
# File        : build.tcl
# Description : MLK-VF02 (XCZU15EG) 工程模式自动化脚本：
#                 1. 打开既有 Vivado 工程（part 已为 xczu15eg-ffvb1156-2-i）
#                 2. 添加核 RTL（排除仿真 riscv_soc.sv）、板级 RTL、XDC
#                 3. 设置 include 路径、顶层，并把固件 hex 绝对路径经 generic 下传
#                 4. 综合 -> 实现 -> 生成 bitstream
#               脚本幂等：重复执行会先移除旧源文件引用（不删除磁盘文件）。
#   Usage      : vivado -mode batch -source build.tcl
#==============================================================================

#------------------------------------------------------------------------------
# 路径基准（全部由脚本位置动态推导，避免硬编码用户名）
#------------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set core_dir   [file dirname $fpga_dir]
set rtl_dir    [file join $core_dir rtl]
set board_dir  [file join $fpga_dir rtl]
set xdc_file   [file join $fpga_dir constrs riscv.xdc]
set hex_file   [file normalize [file join $fpga_dir hex firmware.hex]]
set xpr_file   [file join $fpga_dir RISCV.xpr]

puts "INFO: fpga_dir = $fpga_dir"
puts "INFO: rtl_dir  = $rtl_dir"
puts "INFO: hex_file = $hex_file"

#------------------------------------------------------------------------------
# 打开工程
#------------------------------------------------------------------------------
open_project $xpr_file

#------------------------------------------------------------------------------
# 清理旧引用（保证幂等；仅移除工程引用，不删磁盘文件）
#------------------------------------------------------------------------------
set old_design [get_files -quiet -of_objects [get_filesets sources_1]]
if { [llength $old_design] > 0 } {
    remove_files $old_design
}
set old_constr [get_files -quiet -of_objects [get_filesets constrs_1]]
if { [llength $old_constr] > 0 } {
    remove_files $old_constr
}

#------------------------------------------------------------------------------
# 添加核 RTL（不含仿真用 riscv_soc.sv）
#------------------------------------------------------------------------------
set core_files [list \
    riscv_defines.sv riscv_types.svh \
    alu.sv mul.sv div.sv \
    if_unit.sv id_unit.sv rf_unit.sv ex_unit.sv \
    clint.sv riscv_core.sv]

set core_paths [list]
foreach f $core_files {
    lappend core_paths [file join $rtl_dir $f]
}
add_files -norecurse $core_paths

#------------------------------------------------------------------------------
# 添加板级 RTL（fpga/rtl 下全部 .sv）
#------------------------------------------------------------------------------
add_files -norecurse [glob -type f [file join $board_dir *.sv]]

#------------------------------------------------------------------------------
# 添加约束
#------------------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse $xdc_file

#------------------------------------------------------------------------------
# include 路径、顶层、固件 hex 路径
#   riscv_defines.sv 是 package（经 import 引用），.sv 扩展名会被正常编译，
#   自动编译顺序保证其先于 import 模块；riscv_types.svh 是被 `include 的
#   全局 typedef 头，保持 Header，靠 include_dirs 查找。
#------------------------------------------------------------------------------
set_property include_dirs [list $rtl_dir] [get_filesets sources_1]
set_property top riscv_board [get_filesets sources_1]
set_property generic "HEX_FILE=\"$hex_file\"" [get_filesets sources_1]
update_compile_order -fileset sources_1

# 校验 hex 确实存在，否则 $readmemh 会静默失败导致固件未进 bitstream
if { ![file exists $hex_file] } {
    error "固件 hex 不存在：$hex_file"
}

#------------------------------------------------------------------------------
# 综合
#------------------------------------------------------------------------------
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] ne "100%" } {
    error "综合失败：[get_property STATUS [get_runs synth_1]]"
}
puts "INFO: 综合完成"

#------------------------------------------------------------------------------
# 实现 + 生成 bitstream
#------------------------------------------------------------------------------
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] ne "100%" } {
    error "实现/bitstream 失败：[get_property STATUS [get_runs impl_1]]"
}
puts "INFO: 实现与 bitstream 生成完成"

# 输出 bitstream 路径
set bit_file [file join $fpga_dir RISCV.runs impl_1 riscv_board.bit]
puts "INFO: BITSTREAM = $bit_file"

close_project
puts "INFO: BUILD ALL DONE"
