#==============================================================================
# File        : riscv.xdc
# Description : 米联客 MLK-VF02（XCZU15EG-FFVB1156）板级约束。
#               包含：100MHz 时钟约束、物理引脚绑定与电平标准。
#               引脚号与电平均取自硬件资料「按钮-LED-UART-JTAG 管脚定义表」
#               及「核心模块硬件使用手册」。
#==============================================================================

#------------------------------------------------------------------------------
# 1. 系统时钟：100MHz 差分，周期 10ns（约束在差分正端，IBUFDS 输入）
#------------------------------------------------------------------------------
create_clock -name PL_CLK -period 10.000 [get_ports PL_CLK_P]

#------------------------------------------------------------------------------
# 2. 差分时钟引脚（DIFF_SSTL12）
#------------------------------------------------------------------------------
set_property PACKAGE_PIN  AL6 [get_ports PL_CLK_P]
set_property PACKAGE_PIN  AL5 [get_ports PL_CLK_N]
set_property IOSTANDARD DIFF_SSTL12 [get_ports PL_CLK_P]
set_property IOSTANDARD DIFF_SSTL12 [get_ports PL_CLK_N]

#------------------------------------------------------------------------------
# 3. PL 按键（LVCMOS18，按下为低）
#------------------------------------------------------------------------------
set_property PACKAGE_PIN A20 [get_ports PL_BUT]
set_property IOSTANDARD LVCMOS18 [get_ports PL_BUT]

#------------------------------------------------------------------------------
# 4. PL LED（LVCMOS18，高电平点亮）
#------------------------------------------------------------------------------
set_property PACKAGE_PIN D21 [get_ports PL_LED1]
set_property PACKAGE_PIN D10 [get_ports PL_LED2]
set_property IOSTANDARD LVCMOS18 [get_ports PL_LED1]
set_property IOSTANDARD LVCMOS18 [get_ports PL_LED2]

#------------------------------------------------------------------------------
# 5. PL 串口发送（LVCMOS18，115200 8N1；波特率在 RTL 内分频，无需时钟约束）
#------------------------------------------------------------------------------
set_property PACKAGE_PIN J17 [get_ports FPGA_UART_TXD1]
set_property IOSTANDARD LVCMOS18 [get_ports FPGA_UART_TXD1]

#------------------------------------------------------------------------------
# 6. 配置项（可选）：输出默认驱动强度与转换速率
#------------------------------------------------------------------------------
set_property DRIVE 8 [get_ports {PL_LED1 PL_LED2 FPGA_UART_TXD1}]
set_property SLEW SLOW [get_ports {PL_LED1 PL_LED2 FPGA_UART_TXD1}]
