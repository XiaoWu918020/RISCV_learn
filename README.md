# RV32IM 三级流水线 RISC-V 核与 FreeRTOS 移植

按框图模块划分的三级流水线 RISC-V 核，SystemVerilog 实现，支持 **RV32I 基础整数集 + RV32M 乘除扩展**，含 M 模式最小 CSR、异常与标准 SiFive CLINT 中断。在此基础上搭建最小 SoC（IMEM/DMEM/CLINT 地址译码），并成功裸机移植 **FreeRTOS v202411.00**，在 Icarus Verilog 仿真下验证任务调度与上下文切换。

当前三项仿真全部通过：

| 测试 | testbench | 结果 |
|---|---|---|
| 指令集签名（26 项） | `tb_riscv_core.sv` | PASSED |
| 定时器中断（mtimecmp 配置） | `tb_riscv_soc.sv` | PASSED |
| FreeRTOS 多任务调度 | `tb_freertos.sv` | PASSED |

## 功能特性

- **RV32I**：`add/sub`、`addi`；`and/or/xor` 及立即数版；`sll/srl/sra` 及立即数版；`slt/sltu`、`slti/sltiu`；`lui/auipc`；6 种分支 `beq/bne/blt/bge/bltu/bgeu`；`jal/jalr`；`lb/lh/lw/lbu/lhu`、`sb/sh/sw`；`fence` 按 NOP 处理。
- **RV32M**：`mul/mulh/mulhsu/mulhu`、`div/divu/rem/remu`。
- **CSR（M 模式最小集）**：`mstatus`(MIE/MPIE)、`misa`、`mie`、`mtvec`、`mscratch`、`mepc`、`mcause`、`mtval`、`mip`、`mcycle`、`minstret`；支持 `csrrw/csrrs/csrrc` 及立即数版本。
- **异常与中断**：`ecall`、`ebreak`、`mret`、非法指令、访存非对齐；CLINT 提供软件(msip)/定时器(mtimecmp)/外部三类中断。
- **SoC**：核数据口统一地址译码，IMEM 只读窗口 + DMEM 字节写 + CLINT 转接，读 mux 返回对应从设备数据。
- **FreeRTOS**：抢占式调度、独立 ISR 栈、heap_4 动态内存、mtime 提供 1 ms tick、`ecall` 触发任务切换。
- 异步低复位 `rst_n`，存储器按“组合读 + 时钟沿写”模型对接。

## 目录结构

```
3_stage_pipeline/
├── rtl/
│   ├── riscv_defines.svh   # 常量包：opcode/ALU/立即数/CSR/mcause（须最先编译）
│   ├── riscv_types.svh     # 全局头：打包控制结构 ctrl_bus_t（include guard）
│   ├── if_unit.sv          # 一级 IF：pc + if_id（重定向优先于停顿）
│   ├── id_unit.sv          # 二级 ID：译码 + 立即数 + 转发/冒险 + id_ex
│   ├── rf_unit.sv          # 寄存器单元：gpr + csr（异常/mret 状态机）
│   ├── ex_unit.sv          # 三级 EX：cu + 例化 alu/mul/div（含访存/写回/仲裁）
│   ├── alu.sv              # 算术逻辑部件
│   ├── mul.sv              # RV32M 乘法部件
│   ├── div.sv              # RV32M 除法/取余部件
│   ├── clint.sv            # 核心本地中断器（标准 SiFive 偏移）
│   ├── riscv_core.sv       # 核顶层：例化并互联 IF/ID/RF/EX + CLINT
│   └── riscv_soc.sv        # SoC 顶层：IMEM/DMEM/CLINT 地址译码 + 读 mux
├── tb/
│   ├── mem_model.sv        # imem/dmem 行为模型（核级 testbench 用）
│   ├── tb_riscv_core.sv    # 核级：26 项签名 + CLINT 软件中断驱动
│   ├── tb_riscv_soc.sv     # SoC 级：定时器中断端到端验证
│   ├── tb_freertos.sv      # SoC 级：FreeRTOS 多任务调度验证
│   ├── tb_debug.sv         # 调试用：事件/状态采样（按需重写）
│   ├── riscv_as.py         # RV32IM 汇编器（两遍扫描）
│   ├── test.s / test.hex   # 签名测试程序及其 hex
│   └── timer.s / timer.hex # 定时器测试程序及其 hex
├── freertos_app/           # FreeRTOS 裸机移植与构建
│   ├── link.ld             # 链接脚本：IMEM/DMEM 内存布局
│   ├── startup.S           # 复位入口：设栈/清 bss/拷 data/调 main
│   ├── FreeRTOSConfig.h    # 内核配置（时钟/tick/栈/堆/裁剪）
│   ├── main.c              # 多任务演示 + .probe 观测段
│   ├── support.c           # 裸机运行库：mem* 与软件 __clzsi2
│   ├── elf2hex.py          # ELF32 按 LMA 提取 IMEM 镜像 -> 扁平 hex
│   ├── build.ps1           # 一键构建脚本（xPack 工具链）
│   └── build/              # 构建产物：firmware.elf / firmware.hex / *.o
├── docs/
│   └── riscv_architecture.html  # 五段式结构与信号交互图
└── freeRTOS/               # FreeRTOS 官方源码（v202411.00）
```

## 流水线与冒险

三级流水：**IF（取指）→ ID（译码 + 读寄存器 + 立即数 + 转发/冒险）→ EX（执行 + 访存 + 写回）**，写回合并在 EX 级。

- **EX→ID 转发**：EX 写回结果直接送回 ID 操作数，零停顿解决大部分数据相关。
- **load-use 冒险**：本级使用上一条 load 的目的寄存器时停顿一拍，并向 ID/EX 注气泡。
- **CSR 写后读**：同地址 CSR 写后读停顿一拍。
- **控制冒险**：分支/跳转/异常/中断/mret 均在 EX 级裁决，默认“预测不跳转”；重定向时冲刷 IF/ID 与 ID/EX。**重定向优先级高于停顿**，保证停顿时发生的中断不丢失。
- **中断断点**：异步中断保存 ID 级最年轻未完成指令地址；同步异常保存当前指令地址。

## SoC 地址映射

核数据口地址译码（参数可覆盖，见 `riscv_soc.sv`）：

| 区域 | 基址 | 大小 | 说明 |
|---|---|---|---|
| IMEM | `0x0000_0000` | 16 KB | 代码/只读常量，复位 PC=0；数据口只读 |
| DMEM | `0x2000_0000` | 64 KB | 数据/堆栈/堆，可字节写 |
| CLINT | `0x4000_0000` | 0xC000 窗口 | 中断/定时器（核内 CLINT） |

CLINT 内部标准 SiFive 偏移（相对 CLINT 基址，按 `addr[15:0]` 译码）：

| 偏移 | 寄存器 | 说明 |
|---|---|---|
| `0x0000` | MSIP | 机器软件中断挂起（bit0） |
| `0x4000 / 0x4004` | MTIMECMP 低/高 | 复位全 1，避免误触发 |
| `0xBFF8 / 0xBFFC` | MTIME 低/高 | 64 位计数器，每周期 +1 |

## FreeRTOS 移植

**内存布局（`link.ld`）**：代码与只读数据放 IMEM；`.data` 的 VMA 在 DMEM、LMA 在 IMEM（启动时由 `startup.S` 拷贝）；`.bss`、FreeRTOS 堆、ISR 栈在 DMEM；`.probe` 固定在 DMEM 最前供 testbench 观测。

**关键配置（`FreeRTOSConfig.h`）**：

- `configMTIME_BASE_ADDRESS = 0x4000BFF8`，`configMTIMECMP_BASE_ADDRESS = 0x40004000`
- `configCPU_CLOCK_HZ = 100 MHz`，`configTICK_RATE_HZ = 1000`（每 tick 1 ms，mtime 增量 100000）
- 抢占式调度、`configMAX_PRIORITIES = 7`、`configTOTAL_HEAP_SIZE = 8192`、ISR 栈 256 字
- 动态分配（heap_4），关闭软件定时器/互斥量/队列集以控制体积

**任务设计（`main.c`）**：任务1 优先级 2、每 1 tick 计数；任务2 优先级 1、每 2 tick 计数。无 UART，通过 `.probe` 段（`dmem_mem[0..3]`：cnt1/cnt2/alive/err）观测。

**切换机制**：任务切换用 `ecall`（mcause=11，同步异常，mepc+4）；tick 用 mtime 中断（mcause=0x80000007，异步）。

## 工具链

- **仿真**：Icarus Verilog（`iverilog`/`vvp`，本地 12.0 devel），编译加 `-g2012 -I rtl`，`riscv_defines.svh` 须置于源列表首位。
- **固件编译**：xPack `riscv-none-elf-gcc` 15.2.0，固定 `-march=rv32im_zicsr -mabi=ilp32`，裸机 `-ffreestanding -nostdlib -fno-builtin -Os -mno-relax -fdata-sections -ffunction-sections`，链接 `-Wl,--gc-sections`。GCC 15 起 CSR 指令拆为独立 `zicsr` 扩展，需显式启用。

## 构建与仿真

### 1. 构建 FreeRTOS 固件

在 `freertos_app/` 下运行 PowerShell 脚本，产出 `build/firmware.hex`（当前 5652 字节 / 1413 字，落在 16 KB IMEM 内）：

```powershell
.\build.ps1
```

### 2. 编译并运行仿真

编译需把 `riscv_defines.svh` 放首位；运行目录要能找到对应 hex（FreeRTOS 在 `freertos_app/build`，其余在 `tb`）。

```sh
# FreeRTOS 调度（在 freertos_app/build 运行，firmware.hex 位于该目录）
iverilog -g2012 -I <rtl> -o sim_freertos.vvp <rtl>/riscv_defines.svh <rtl>/*.sv <tb>/tb_freertos.sv
vvp sim_freertos.vvp

# 26 项签名（在 tb 运行，test.hex 位于该目录）
iverilog -g2012 -I <rtl> -o sig.vvp <rtl>/riscv_defines.svh <rtl>/*.sv <tb>/mem_model.sv <tb>/tb_riscv_core.sv
vvp sig.vvp

# 定时器中断（在 tb 运行，timer.hex 位于该目录）
iverilog -g2012 -I <rtl> -o soc.vvp <rtl>/riscv_defines.svh <rtl>/*.sv <tb>/tb_riscv_soc.sv
vvp soc.vvp
```

通过时分别输出：

```
==== FREERTOS TEST PASSED: 两任务均被调度且计数增长，上下文切换正常 ====
==== TEST PASSED: 全部 26 项签名校验通过 ====
==== TIMER IRQ TEST PASSED: mtimecmp 配置并进入定时器中断 ====
```

FreeRTOS 仿真实测：调度器 39252 周期启动，任务1 计数 1→10、任务2 0→5（约 2:1，符合 tick 设计），`err=0`。

## 调试记录（两个关键根因）

1. **SoC 数据口无法读 IMEM 常量**：数据口地址译码最初只接 DMEM/CLINT，读 IMEM 区域的 `xISRStackTop`（0x1600）返回 0，导致 ISR 栈指针 sp=0、栈操作越界、`ret` 跳 0 反复重启。修复：`riscv_soc.sv` 新增 IMEM 只读选择与读 mux 分支。
2. **中断重定向被停顿挡掉**：中断在 EX 接受的同一周期 ID 请求停顿，PC 更新被 `if (!stall)` 挡住，下一拍中断指令已冲刷，重定向丢失，表现为 mtimecmp 停更、`mie=0`、idle 空转。修复：`if_unit.sv` 让 PC 重定向与 IF/ID 冲刷优先于停顿。

## Icarus 兼容性注意事项

- 不支持 package 内 `typedef` 直接作模块 ANSI 端口：控制结构 `ctrl_bus_t` 放在独立全局头 `riscv_types.svh`（带 include guard），由各模块 `include`。
- 不支持 `localparam int/parameter int` 类型标注：统一改为显式 `logic` 位宽。
- 编译顺序：`riscv_defines.svh`（package）必须在引用它的模块之前。
- `priority/unique case` 在复位等未初始化状态可能报 unhandled 警告，属 iverilog 提示，不影响仿真结果。
