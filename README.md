# RV32IM 三级流水线 RISC-V 核与 FreeRTOS 移植

本工程实现一个自研三级流水线 RV32IM RISC-V 核，并在其上完成 FreeRTOS v202411.00 移植、RTL 长回归、Vivado 综合实现以及米联客 MLK-VF02（XCZU15EG）真实板级验证。

当前最终版本已在开发板上持续输出 task1/task2 计数，证明 Tick 中断、任务切换、上下文保存/恢复、`mret`、任务延时和 UART 链路均已打通。

## 1. 当前验证状态

| 测试/验证 | 模块 | 结果 |
|---|---|---|
| 指令集签名 | `tb/tb_riscv_core.sv` | 26 项 PASSED |
| 定时器中断 | `tb/tb_riscv_soc.sv` | PASSED |
| FreeRTOS 早期仿真 | `tb/tb_freertos.sv` | PASSED |
| FPGA RTL 长回归 | `tb/tb_fpga_rtl.sv` | PASSED，200 万周期 |
| 板级诊断 | `riscv_board_status.bit` | LED1 常亮、LED2 闪烁、UART 收到 `41 42` |
| 板级 FreeRTOS | `riscv_board_freertos_irqfix.bit` | 串口持续更新 task1/task2 计数 |

长回归结果：

```text
task1: 1 → 68
task2: 0 → 33
无同步异常
==== FPGA-RTL TEST PASSED ====
```

## 2. 开发环境

| 项目 | 配置 |
|---|---|
| 目标器件 | `xczu15eg-ffvb1156-2-i` |
| 开发板 | 米联客 MLK-VF02 |
| FPGA 工具 | Vivado 2023.2 |
| 固件工具链 | xPack `riscv-none-elf-gcc` 15.2.0 |
| 仿真工具 | Icarus Verilog |
| 板级输入时钟 | 100 MHz 差分 PL 时钟 |
| 系统时钟 | MMCM 输出 25 MHz |
| UART | 115200、8N1，25 MHz 下 BAUD_DIV=217 |
| RTOS | FreeRTOS v202411.00 |

工具链路径：

```text
C:\Users\19117\Desktop\work\RISC-V\tools\xpack-riscv-none-elf-gcc-15.2.0-1\bin
```

GCC 15 下 CSR 已拆分为独立扩展，编译参数固定为：

```text
-march=rv32im_zicsr -mabi=ilp32
```

## 3. 功能特性

- **RV32I**：算术逻辑、移位、比较、分支、`jal/jalr`、load/store、`fence`。
- **RV32M**：`mul/mulh/mulhsu/mulhu`、`div/divu/rem/remu`。
- **M 模式最小 CSR**：`mstatus`、`misa`、`mie`、`mtvec`、`mscratch`、`mepc`、`mcause`、`mtval`、`mip`、`mcycle`、`minstret`。
- **异常与中断**：支持 `ecall`、`ebreak`、`mret`、非法指令、访存非对齐、CLINT 软件/定时器/外部中断。
- **FreeRTOS**：抢占式调度、时间片、独立 ISR 栈、heap_4、1 ms Tick、任务通知。
- **板级外设**：轮询 UART、GPO LED、MMCM、复位同步器、CLINT 定时器。

## 4. 目录结构

```text
3_stage_pipeline/
├── rtl/                         # CPU 核心 RTL
│   ├── riscv_defines.sv         # 常量定义（原 .svh 已改为 .sv）
│   ├── riscv_types.svh
│   ├── if_unit.sv               # PC 与 IF/ID，重定向优先于停顿
│   ├── id_unit.sv               # 译码、立即数、冒险控制
│   ├── rf_unit.sv               # GPR 与 CSR
│   ├── ex_unit.sv               # 执行、访存、写回、中断断点修复
│   ├── alu.sv
│   ├── mul.sv
│   ├── div.sv
│   ├── clint.sv
│   ├── riscv_core.sv
│   └── riscv_soc.sv
├── fpga/
│   ├── rtl/                     # 上板 SoC 与板级模块
│   │   ├── riscv_soc_fpga.sv    # 双 ROM + DMEM/UART/GPO/CLINT
│   │   ├── fpga_rom.sv          # 单异步读初始化 ROM
│   │   ├── fpga_ram.sv          # 同步字节写、异步读 RAM
│   │   ├── uart.sv              # 轮询 UART
│   │   ├── riscv_board.sv       # MMCM、复位、LED 板级顶层
│   │   └── riscv_board_diag.sv
│   ├── constrs/riscv.xdc        # 板级引脚与时序约束
│   ├── hex/firmware.hex         # Vivado 正式构建使用的固件
│   ├── scripts/                 # 构建、诊断、仿真和排查脚本
│   ├── release/                 # 已验证的最终 bitstream 与时序报告
│   ├── baremetal_min/           # 最小 GPO 裸机实验
│   ├── baremetal_uart/          # UART 裸机实验
│   └── RISCV.xpr
├── freertos_app/
│   ├── main.c                   # 双任务演示、UART 临界区、GPO
│   ├── FreeRTOSConfig.h         # 25 MHz、1 kHz Tick、堆栈配置
│   ├── startup.S
│   ├── link.ld
│   ├── support.c
│   ├── elf2hex.py
│   └── build.ps1
├── tb/                          # 各类 testbench
├── docs/
└── FreeRTOS移植问题排查记录.md
```

`freeRTOS/` 为第三方官方源码目录，已在 `.gitignore` 中忽略；需要单独下载 FreeRTOS v202411.00 后放入工程。

## 5. 地址映射

| 区域 | 基址 | 大小/窗口 | 说明 |
|---|---:|---:|---|
| IMEM | `0x0000_0000` | 16 KB | 指令与只读数据 |
| UART | `0x1000_0000` | 0x100 | offset 0：写发送字符，读 bit0=tx_ready |
| GPO | `0x1000_1000` | 0x100 | bit0/bit1 驱动 LED |
| DMEM | `0x2000_0000` | 64 KB | 数据、堆、任务栈、ISR 栈 |
| CLINT | `0x4000_0000` | 0xC000 | 中断与定时器 |
| mtimecmp | `0x4000_4000` | 64 位 | 定时器比较值 |
| mtime | `0x4000_BFF8` | 64 位 | 每系统周期加一 |

## 6. FreeRTOS 配置

关键配置位于 `freertos_app/FreeRTOSConfig.h`：

```c
#define configCPU_CLOCK_HZ              25000000UL
#define configTICK_RATE_HZ              1000UL
#define configUSE_PREEMPTION            1
#define configUSE_TIME_SLICING          1
#define configMINIMAL_STACK_SIZE        128
#define configTOTAL_HEAP_SIZE           8192
#define configISR_STACK_SIZE_WORDS      256
#define configCHECK_FOR_STACK_OVERFLOW  2
```

当前演示任务：

| 任务 | 优先级 | 周期 | 打印条件 |
|---|---:|---:|---|
| task1 | 2 | 1 ms | 每计数 10 次 |
| task2 | 1 | 2 ms | 每计数 5 次 |

任务主动切换通过 `ecall` 进入 RISC-V trap；周期调度由 CLINT 机器定时器中断触发。`main()` 中显式安装：

```c
__asm volatile ("csrw mtvec, %0" : : "r" (freertos_risc_v_trap_handler));
```

## 7. 构建固件

在工程根目录执行：

```powershell
& ".\freertos_app\build.ps1"
```

输出：

```text
freertos_app/build/firmware.elf
freertos_app/build/firmware.hex
```

当前固件包含 **1583 个 32 位字，即 6332 字节**，位于 16 KB IMEM 内。

更新 Vivado 正式镜像：

```powershell
Copy-Item ".\freertos_app\build\firmware.hex" ".\fpga\hex\firmware.hex" -Force
```

## 8. RTL 长回归

在 `freertos_app/build` 目录下运行，使 testbench 能找到相对路径 `firmware.hex`：

```powershell
$srcs = @(
    Get-ChildItem ..\..\rtl\*.sv | ForEach-Object { $_.FullName }
) + @(
    (Resolve-Path ..\..\fpga\rtl\fpga_ram.sv),
    (Resolve-Path ..\..\fpga\rtl\fpga_rom.sv),
    (Resolve-Path ..\..\fpga\rtl\uart.sv),
    (Resolve-Path ..\..\fpga\rtl\riscv_soc_fpga.sv),
    (Resolve-Path ..\..\tb\tb_fpga_rtl.sv)
)

iverilog -g2012 -I ..\..\rtl -o sim_fpga_rtl.vvp $srcs
vvp .\sim_fpga_rtl.vvp
```

通过标志：

```text
==== FPGA-RTL TEST PASSED ====
```

## 9. FPGA 上板构建

执行 Vivado 批处理：

```powershell
& "D:\vivado\2023.2\bin\vivado.bat" -mode batch -source ".\fpga\scripts\build.tcl"
```

最终已验证文件：

```text
fpga/release/riscv_board_freertos_irqfix.bit
fpga/release/riscv_board_freertos_irqfix_timing.rpt
```

时序结果：

```text
WNS = +7.149 ns
TNS = 0
失败端点 = 0
All user specified timing constraints are met.
```

串口参数：**COM3、115200、8N1、文本模式**。

正常输出示例：

```text
==== FreeRTOS on RV32IM (3-stage) start ====
[task2] count=5
[task1] count=10
[task2] count=10
[task1] count=20
...
```

## 10. 板级关键引脚

| 信号 | 引脚 | 说明 |
|---|---|---|
| PL_CLK_P/N | `AL6/AL5` | 100 MHz 差分时钟 |
| PL_LED1 | `D21` | 高电平点亮 |
| PL_LED2 | `D10` | 高电平点亮 |
| PL_BUT | `A20` | 按下为低 |
| FPGA_UART_TXD1 | `J17` | FPGA 发送 |
| FPGA_UART_RXD1 | `H17` | FPGA 接收 |

## 11. 今日问题与根因汇总

| 问题 | 排查关键 | 根因 | 解决方案 |
|---|---|---|---|
| GCC 不生成 ELF | 检查文件大小、inode、磁盘空间、cc1 | Linux gcc driver 为 0 字节 | 改用 Windows xPack GCC 15.2.0 |
| ISR 栈指针为 0 | 跟踪 `xISRStackTop` load | 数据口不能读 IMEM 常量 | 增加 IMEM 只读数据窗口 |
| 定时器中断丢失 | 观察 PC、mtimecmp、stall | 重定向被停顿挡住 | 重定向优先于停顿 |
| 100 MHz 时序失败 | 查看 WNS/TNS | 组合路径过长 | MMCM 降至 25 MHz |
| 上板无现象 | LED、UART、裸机、综合后仿真逐步二分 | 双异步读 IMEM 综合映射异常 | 拆为两份单异步读 ROM |
| 串口日志混杂 | 分析 tx_ready 与写 TDR 时序 | 两任务在检查和写入之间抢占 | 整条日志放入临界区 |
| 运行约 50 tick 后停止 | 读取 mcause/mepc/mtval 并跟踪上下文 | 中断命中 `ret` 时错存 `ret+4` | 中断保存实际下一 PC |

最终中断断点修复位于 `rtl/ex_unit.sv`：

```systemverilog
always_comb begin
    if (ctrl_i.jump)
        irq_next_pc = branch_target;
    else if (ctrl_i.jalr)
        irq_next_pc = jalr_target;
    else if (branch_taken)
        irq_next_pc = branch_target;
    else if (id_valid_i)
        irq_next_pc = id_pc_i;
    else
        irq_next_pc = pc_i + 32'd4;
end

assign exc_epc_o = sync_exc ? pc_i : irq_next_pc;
```

## 12. 调试方法总结

1. 先验证时钟、引脚、LED，再验证 UART、裸机、CPU 取指，最后调试 FreeRTOS。
2. 仿真必须运行到超过历史故障点，不能只验证“任务曾经启动”。
3. 串口混杂和永久停止是两个不同问题，不能用一个根因强行解释。
4. 综合前 RTL 通过不代表综合后硬件正确，必要时做综合后功能仿真。
5. 随机死机优先采集 `mcause`、`mepc`、`mtval`、PC 和寄存器现场，再结合反汇编定位。
6. 异步中断保存的是当前指令提交后的实际执行地址，控制转移指令不能简单取 `pc+4`。

## 13. 相关资料

- 详细问题复盘：`FreeRTOS移植问题排查记录.md`
- GitHub 仓库：`https://github.com/XiaoWu918020/RISCV_learn`
- 官方 FreeRTOS：v202411.00
