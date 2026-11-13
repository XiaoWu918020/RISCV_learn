# RV32IM 三级流水线 RISC-V 核

按框图模块划分的三级流水线 RISC-V 核，SystemVerilog 实现，支持 **RV32I 基础整数集 + RV32M 乘除扩展**，含 M 模式最小 CSR 集合、异常与 CLINT 中断。已在 Icarus Verilog 11.0 下通过全部 26 项功能签名校验。

## 功能特性

- **RV32I**：`add/sub`、`addi`；`and/or/xor` 及立即数版；`sll/srl/sra` 及立即数版；`slt/sltu`、`slti/sltiu`；`lui/auipc`；6 种分支 `beq/bne/blt/bge/bltu/bgeu`；`jal/jalr`；`lb/lh/lw/lbu/lhu`、`sb/sh/sw`；`fence` 按 NOP 处理。
- **RV32M**：`mul/mulh/mulhsu/mulhu`、`div/divu/rem/remu`。
- **CSR（M 模式最小集）**：`mstatus`(MIE/MPIE)、`misa`、`mie`、`mtvec`、`mscratch`、`mepc`、`mcause`、`mtval`、`mip`、`mcycle`、`minstret`；支持 `csrrw/csrrs/csrrc` 及立即数版本。
- **异常与中断**：`ecall`、`ebreak`、`mret`、非法指令、访存非对齐；CLINT 提供软件(msip)/定时器(mtimecmp)/外部三类中断。
- 异步低复位 `rst_n`，存储器按“组合读 + 时钟沿写”模型对接。

## 目录结构

```
3_stage_pipeline/
├── rtl/
│   ├── riscv_defines.svh   # 常量包：opcode/ALU/立即数/CSR/mcause（须最先编译）
│   ├── riscv_types.svh    # 全局头：打包控制结构 ctrl_bus_t（include guard）
│   ├── if_unit.sv         # 一级 IF：pc + if_id
│   ├── id_unit.sv         # 二级 ID：译码 + 立即数 + 转发/冒险 + id_ex
│   ├── rf_unit.sv         # 寄存器单元：gpr + csr
│   ├── ex_unit.sv         # 三级 EX：cu + 例化 alu/mul/div（含访存/写回）
│   ├── alu.sv             # 算术逻辑部件
│   ├── mul.sv             # RV32M 乘法部件
│   ├── div.sv             # RV32M 除法/取余部件
│   ├── clint.sv           # 核心本地中断器
│   └── riscv_core.sv      # 顶层：例化并互联五大单元
└── tb/
    ├── mem_model.sv       # imem/dmem 行为模型（组合读、字节掩码写）
    ├── tb_riscv_core.sv   # 顶层 testbench：26 项签名 + CLINT 驱动
    ├── riscv_as.py        # RV32IM 汇编器（两遍扫描）
    ├── test.s             # 测试汇编程序（146 条指令）
    └── test.hex           # 汇编产物（Verilog hex）
```

## 流水线与冒险

三级流水：**IF（取指）→ ID（译码 + 读寄存器 + 立即数 + 转发/冒险）→ EX（执行 + 访存 + 写回）**，写回合并在 EX 级。

- **EX→ID 转发**：EX 写回结果直接送回 ID 操作数，零停顿解决大部分数据相关。
- **load-use 冒险**：检测到本级使用上一条 load 的目的寄存器时停顿一拍，并向 ID/EX 注气泡。
- **CSR 写后读**：同地址 CSR 写后读停顿一拍。
- **控制冒险**：分支/跳转/异常/中断均在 EX 级裁决，默认“预测不跳转”；重定向时冲刷 IF/ID 与 ID/EX。
- **中断断点**：异步中断保存 ID 级最年轻未完成指令地址；同步异常保存当前指令地址。

## 地址布局

| 区域 | 地址 | 说明 |
|---|---|---|
| 数据区 | `0x1000` | 测试数据 |
| 签名区 | `0x2000 ~ 0x2064` | 26 项结果，`done` 标志在 `0x2064` |
| 中断握手 | `0x3000` | msip 处理完成标志 |

CLINT 内部映射（地址低 5 位）：`0x00` msip、`0x08/0x0C` mtimecmp 低/高、`0x10/0x14` mtime 低/高。

## 编译与仿真

依赖 Icarus Verilog（iverilog/vvp）。在 `tb/` 目录下执行：

```sh
# 1) 汇编测试程序（修改 test.s 后重新生成 hex）
python riscv_as.py test.s test.hex

# 2) 编译（-g2012 启用 SystemVerilog，-I 指定 include 路径）
iverilog -g2012 -I../rtl -o sim.out \
  ../rtl/riscv_defines.svh ../rtl/riscv_types.svh \
  ../rtl/alu.sv ../rtl/mul.sv ../rtl/div.sv \
  ../rtl/if_unit.sv ../rtl/id_unit.sv ../rtl/rf_unit.sv ../rtl/ex_unit.sv \
  ../rtl/clint.sv ../rtl/riscv_core.sv \
  mem_model.sv tb_riscv_core.sv

# 3) 运行
vvp sim.out
```

通过时输出：

```
==== TEST PASSED: 全部 26 项签名校验通过 ====
```

## Icarus Verilog 11 兼容性注意事项

- 不支持 package 内 `typedef` 直接作模块 ANSI 端口：控制结构 `ctrl_bus_t` 放在独立全局头 `riscv_types.svh`（带 include guard），由各模块 `include`。
- 不支持 `localparam int/parameter int` 类型标注：统一改为显式 `logic` 位宽。
- testbench `task` 内变量声明须置于任务开头。
- 编译顺序：`riscv_defines.svh`（package）必须在引用它的模块之前。
- 可能出现 `sorry: constant selects in always_* processes` 警告，属 iverilog 提示，part select 功能正确，不影响仿真结果。
