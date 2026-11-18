#==============================================================================
# File        : program.tcl
# Description : MLK-VF02（XCZU15EG）JTAG 自动烧录脚本（工程模式，批处理）。
#               前提：开发板已上电、JTAG 下载器已连接并被系统识别。
#               自动打开本地 hw_server，连接第一个目标，对 xczu15eg 器件下载
#               riscv_board.bit（PL 临时映像，断电丢失，需重新烧录）。
#   Usage      : vivado -mode batch -source program.tcl
#==============================================================================

#------------------------------------------------------------------------------
# 路径基准（由脚本位置动态推导）
#------------------------------------------------------------------------------
set script_dir [file dirname [file normalize [info script]]]
set fpga_dir   [file dirname $script_dir]
set bit_file   [file normalize [file join $fpga_dir RISCV.runs impl_1 riscv_board.bit]]

if { ![file exists $bit_file] } {
    error "bitstream 不存在：$bit_file（请先运行 build.tcl）"
}
puts "INFO: bitstream = $bit_file"

#------------------------------------------------------------------------------
# 打开硬件管理器并连接本地 hw_server
#------------------------------------------------------------------------------
open_hw_manager
connect_hw_server -allow_non_jtag -url local:localhost:3121

#------------------------------------------------------------------------------
# 枚举并打开第一个硬件目标（JTAG 链）
#------------------------------------------------------------------------------
set targets [get_hw_targets -quiet]
if { [llength $targets] == 0 } {
    error "未检测到 JTAG 目标：请确认下载器连接、开发板上电、驱动已安装"
}
current_hw_target [lindex $targets 0]
open_hw_target

#------------------------------------------------------------------------------
# 选择 xczu15eg PL 器件（优先按名称匹配，否则取最后一个器件）
#------------------------------------------------------------------------------
set devices [get_hw_devices -quiet {*xczu15eg*}]
if { [llength $devices] == 0 } {
    set devices [get_hw_devices -quiet]
}
set device [lindex $devices end]
current_hw_device $device
puts "INFO: programming device = $device"

#------------------------------------------------------------------------------
# 指定 bitstream 并烧录
#------------------------------------------------------------------------------
set_property PROGRAM.FILE $bit_file $device
program_hw_devices $device
puts "INFO: PROGRAM DONE"

#------------------------------------------------------------------------------
# 收尾（保持器件运行，不断开 hw_server 也可；此处仅关闭目标）
#------------------------------------------------------------------------------
close_hw_target
disconnect_hw_server
puts "INFO: JTAG PROGRAM ALL DONE"
