# FreeRTOS 移植与 FPGA 上板问题排查记录

> 适用工程：自研三级流水线 RV32IM 核 + FreeRTOS v202411.00 + 米联客 MLK-VF02（XCZU15EG）  
> 记录目的：按“现象 → 排查步骤 → 根因 → 解决方案 → 验证结果”复盘整个移植过程，供后续调试与学习使用。  
> 当前状态：开发板串口已能持续输出 task1/task2 计数，说明调度器、Tick 中断、任务切换、任务延时和 UART 已在真实硬件上打通。

---

## 1. 最终运行环境

| 项目 | 配置 |
|---|---|
| CPU | 自研三级流水线 RV32IM，M 模式最小 CSR、异常/中断、mret |
| RTOS | FreeRTOS v202411.00，抢占式调度，heap_4 |
| 开发板 | 米联客 MLK-VF02，XCZU15EG |
| 输入时钟 | 100 MHz 差分 PL 时钟 |
| 系统时钟 | MMCM 降频至 25 MHz |
| FreeRTOS Tick | 1 kHz，即 1 ms/tick，25000 个系统周期/tick |
| UART | 115200、8N1，25 MHz 下 BAUD_DIV=217 |
| 固件工具链 | Windows xPack `riscv-none-elf-gcc` 15.2.0 |
| FPGA 工具 | Vivado 2023.2 |
| 串口观察 | COM3、115200、8N1；诊断字节用 HEX，任务日志用文本模式 |

### 1.1 SoC 地址映射

| 区域 | 地址 | 大小/窗口 | 用途 |
|---|---:|---:|---|
| IMEM | `0x0000_0000` | 16 KB | 指令与只读数据 |
| UART | `0x1000_0000` | 0x100 | offset 0：写发送字符，读 bit0=tx_ready |
| GPO | `0x1000_1000` | 0x100 | bit0/bit1 驱动 LED |
| DMEM | `0x2000_0000` | 64 KB | 数据、堆、任务栈、ISR 栈 |
| CLINT | `0x4000_0000` | 0xC000 | 软件/定时器/外部中断 |
| mtimecmp | `0x4000_4000` | 64 位 | 定时器比较值 |
| mtime | `0x4000_BFF8` | 64 位 | 每个系统周期加一 |

### 1.2 演示任务

- task1：优先级 2，每 1 tick 计数一次，每 10 次打印。
- task2：优先级 1，每 2 tick 计数一次，每 5 次打印。
- 正常运行时，task1 的计数值总体约为 task2 的两倍。
- `g_probe[0..3]` 分别记录 task1 计数、task2 计数、alive、error，供 RTL 仿真直接观察。

---

## 2. 问题总览

| 阶段 | 现象 | 最终根因 | 解决方向 |
|---|---|---|---|
| Linux 工具链 | gcc 返回 0 但没有 ELF | gcc driver 是 0 字节文件 | 改用 Windows xPack 工具链 |
| 早期 FreeRTOS 仿真 | ISR 栈指针为 0，反复重启 | SoC 数据口不能读取 IMEM 中的 `xISRStackTop` | 增加 IMEM 数据口只读窗口 |
| 定时器中断 | 中断偶发丢失，idle 空转 | EX 重定向被 ID 停顿挡住 | PC 重定向和流水线冲刷优先于停顿 |
| FPGA 存储器 | 直接换同步 BRAM 后无法工作 | 当前流水线依赖当拍组合读 | 保留异步读模型，暂不改同步 BRAM |
| FPGA 时序 | 100 MHz 下 WNS 约 -17.7 ns | 组合除法器、异步 RAM、EX 路径过长 | MMCM 降至 25 MHz，并同步修改 RTOS 时钟 |
| 上板不启动 | LED 无预期现象、串口无输出 | 综合后 IMEM 取指错误，PC 在 0/4/8 循环 | 改为两份单异步读 ROM |
| 串口日志混杂 | 两个任务的字符交叉、丢字符 | `tx_ready` 检查与写 TDR 之间发生任务抢占 | 整条日志放入临界区 |
| 运行约 50 tick 后停止 | 串口永久不更新 | 中断与 `ret` 同拍时，mepc 错存为 `ret+4` | 中断断点改为实际下一执行地址 |

---

## 3. Linux GCC 不生成 ELF

### 3.1 现象

执行编译命令后，gcc 没有给出有效错误，但目标 ELF 文件不存在。进一步发现：

```text
/home/Riscv_Tools/bin/riscv32-unknown-elf-gcc
/home/Riscv_Tools/bin/riscv32-unknown-elf-gcc-11.1.0
```

两个文件大小都是 **0 字节**，而且 inode 都是 `31221771`，说明它们是同一文件的硬链接，不是“一个有内容、另一个没内容”。

### 3.2 排查步骤

1. 检查真实二进制大小，而不只看命令返回值：

   ```sh
   ls -l /home/Riscv_Tools/bin/riscv32-unknown-elf-gcc-11.1.0
   ```

2. 检查两个 gcc 名称是否共享 inode：

   ```sh
   ls -i /home/Riscv_Tools/bin/riscv32-unknown-elf-gcc \
         /home/Riscv_Tools/bin/riscv32-unknown-elf-gcc-11.1.0
   ```

3. 搜索整个工具链中的 0 字节文件：

   ```sh
   find /home/Riscv_Tools -type f -size 0
   ```

   结果表明并非整个工具链全部损坏；大量 man 手册为 0 字节不影响编译，真正致命的是 bin 下的 gcc driver。

4. 排除磁盘写满：

   ```sh
   df -h /home
   ```

   `/home` 仍有约 270 GB 可用，排除空间不足导致文件截断。

5. 检查编译核心和其他工具：

   - `cc1`、`cc1plus`、`lto1` 等文件仍存在且大小正常。
   - `as`、`ld`、`objcopy`、`readelf` 大小正常。
   - 但 gcc driver 已损坏，无法靠这些文件直接恢复完整编译流程。

6. 搜索原始安装包，未找到可单独提取 gcc driver 的 RISC-V 工具链压缩包；唯一的 `lib.tar.gz` 是工艺库，与 gcc 无关。

### 3.3 根因

**gcc 前端驱动程序损坏为 0 字节。** `cc1` 完好并不代表整个 gcc 能工作，因为 driver 还负责选项解析、调用编译器/汇编器/链接器等流程。

### 3.4 解决方案

改用 Windows xPack 工具链：

```text
C:\Users\19117\Desktop\work\RISC-V\tools\xpack-riscv-none-elf-gcc-15.2.0-1\bin
```

统一使用 `riscv-none-elf-gcc` 15.2.0，并在编译参数中显式指定：

```text
-march=rv32im_zicsr -mabi=ilp32
```

GCC 将 CSR 指令拆分为独立的 `zicsr` 扩展后，仅写 `rv32im` 可能出现 CSR 指令不支持的问题，因此必须显式加上 `_zicsr`。

### 3.5 经验

- “命令返回 0”不等于“生成了正确文件”，必须检查 ELF 是否真实存在。
- 工具链排障应先检查二进制大小、inode、关键组件和磁盘空间，再决定是否重装。
- 不要继续围绕已经确认损坏的 gcc driver 修改编译参数。

---

## 4. 早期 FreeRTOS 仿真中的两个基础问题

### 4.1 数据口无法读取 IMEM 常量

**现象：** ISR 栈指针变成 0，后续栈访问越界，`ret` 跳到 0，程序反复重启。

**排查：** 跟踪 `xISRStackTop` 的读取过程，发现它作为只读常量位于 IMEM，而原 SoC 数据口只译码 DMEM/CLINT，读取 IMEM 地址时默认返回 0。

**解决：** 在 SoC 数据口增加 IMEM 只读窗口及读 mux 分支，使 CPU 能通过 load 读取 IMEM 中的常量。

**经验：**  Harvard 风格的“取指口”和“数据口”可以同时存在，但只要程序有只读数据位于 IMEM，数据口就必须支持相应的只读访问。

### 4.2 中断重定向被停顿挡住

**现象：** 定时器中断偶发丢失，`mtimecmp` 不再更新，系统停在 idle。

**根因：** EX 级接受中断的同一周期，ID 级请求停顿；PC 更新逻辑被 `if (!stall)` 挡住，而中断入口指令随后又被冲刷，导致重定向丢失。

**解决：** 在 `if_unit.sv` 中规定：

```text
异常/中断/分支等重定向 > 停顿
```

**经验：** 流水线控制必须明确优先级。重定向代表控制流已经改变，不能再被旧路径上的停顿条件否决。

---

## 5. FPGA 存储器与时序约束

### 5.1 为什么不能直接换同步 BRAM

当前三级流水线的取指和 load 都依赖**当拍组合读**。如果直接换成同步读 BRAM，数据要到下一拍才有效，而现有 IF/ID、ID/EX 和冒险控制并未为此增加等待状态。

因此，在未重构流水线前，不能简单把异步读 RAM 替换为同步 BRAM。当前 FPGA 版本采用异步读分布式 LUT RAM/ROM。

后续若一定要使用 BRAM，需要同时修改：

- IF 级取指等待机制；
- load 数据等待与停顿机制；
- 流水线 valid/flush/stall 控制；
- 相应 testbench。

### 5.2 100 MHz 时序不收敛

**现象：** 初版 100 MHz 下 WNS 约 -17.7 ns。

**原因：** 组合除法器、异步读 RAM 和 EX 组合路径叠加，无法在 10 ns 周期内收敛。

**解决：** 使用 MMCM 将系统时钟降至 25 MHz：

```text
100 MHz 输入 → VCO 1000 MHz → CLKOUT0_DIVIDE_F=40 → 25 MHz
```

同时必须修改：

```c
#define configCPU_CLOCK_HZ   25000000UL
#define configTICK_RATE_HZ   1000UL
```

这样一个 Tick 对应 `25000` 个 mtime 周期，仍然保持 1 ms。

**经验：** FPGA 降频后，不能只改 XDC 或 MMCM；RTOS 的 CPU 时钟、UART 波特率分频和延时换算也必须同步修改。

---

## 6. 上板完全不启动：分层排查与双 ROM 修复

### 6.1 排查原则

不要一开始就同时怀疑时钟、复位、UART、CPU 和 FreeRTOS。应按以下顺序逐层二分：

```text
时钟/引脚 → LED → UART 模块与物理链路 → 裸机 GPO → 裸机 UART
→ 复位 → CPU 取指 → FreeRTOS 调度
```

### 6.2 第一步：独立验证时钟和 LED

制作不依赖 CPU 的诊断设计：

- LED1 接 MMCM `locked`；
- LED2 接自由运行计数器。

板上出现 **LED1 常亮、LED2 闪烁**，证明：

- 100 MHz 输入时钟正常；
- MMCM 能锁定；
- LED 引脚、电平极性和约束正确。

### 6.3 第二步：独立验证 UART

- UART RTL 单元测试中，`0x41/0x42/0x55` 均能被正确解码。
- 用户另外完成 UART 回环实验并成功，进一步证明物理串口链路可用。
- 裸机诊断固件最终上板收到 HEX `41 42`，即 ASCII `A B`。

因此，后续 FreeRTOS 无输出不能简单归因于 UART 模块损坏。

### 6.4 第三步：最小裸机 GPO/UART 固件

最小固件依次执行：

1. 写 GPO；
2. 延时；
3. 发送 `A`；
4. 改写 GPO；
5. 发送 `B`；
6. 进入循环。

裸机阶段能够缩小问题范围：如果裸机也不运行，就不是 FreeRTOS 配置问题。

### 6.5 第四步：综合后仿真定位 PC

整板综合后功能仿真发现：

- PC 只在字节地址 `0、4、8` 循环；
- IF/ID 中实际指令与 hex 不一致；
- CPU 因错误取指反复异常回到 0。

最初尝试显式地址切片，虽然消除了跨层级位宽警告，但综合后 PC 仍然循环，说明切片不是充分修复。

### 6.6 根因与解决

原 IMEM 是“同一存储数组双异步读 + 初始化”。Vivado 2023.2 对这种结构的综合映射出现异常，导致实际网表取指错误。

最终将 IMEM 拆成两份单异步读 ROM：

```text
u_imem_fetch：只供 IF 取指
u_imem_data ：只供数据口读取 IMEM 只读窗口
```

核心文件：

```text
fpga/rtl/fpga_rom.sv
fpga/rtl/riscv_soc_fpga.sv
```

代价是多一份 16 KB 镜像，但避开了问题映射结构，且不需要重构当前组合读流水线。

### 6.7 验证结果

双 ROM 诊断 bitstream 上板后：

- LED1 常亮；
- LED2 闪烁；
- UART 收到 `41 42`。

至此，真实硬件上的**启动、取指、执行、GPO 和 UART 发送链路**均已独立验证。

---

## 7. FreeRTOS 串口日志交叉与丢字符

### 7.1 典型现象

```text
[task2] coun[task1] cout=10
t=5
```

这说明两个任务都在运行，但日志不是一个任务完整打印后再轮到另一个任务。

### 7.2 根因

原发送逻辑为：

```c
while ((UART_STATUS_REG & 1U) == 0U) {}
UART_TDR_REG = c;
```

可能发生以下交错：

1. task1 读到 `tx_ready=1`；
2. 在 task1 写 TDR 之前发生 Tick，中断切换到 task2；
3. task2 也读到空闲并写入字符，UART 开始发送；
4. task1 恢复后继续写 TDR；
5. UART 只在 IDLE 状态接受写命令，忙时写会被忽略，于是 task1 的字符丢失。

该竞态能够解释**交叉打印和丢字符**，但 UART 在停止位结束后会回到 IDLE，因此它不能单独解释“永久停止”。

### 7.3 解决方案

在 `freertos_app/main.c` 中，把一整行日志作为原子操作：

```c
static void uart_print_count(const char *tag, uint32_t value)
{
    taskENTER_CRITICAL();
    uart_puts(tag);
    uart_print_dec(value);
    uart_puts("\r\n");
    taskEXIT_CRITICAL();
}
```

临界区只关闭 CPU 中断，UART 和 mtime 硬件仍继续运行。

### 7.4 注意点

- 该方案适合当前小演示，能避免两个任务交叉写 UART。
- 整条日志发送期间会屏蔽中断，可能延迟 Tick 响应；对实时性要求更高时，后续可改为 UART 互斥量、发送队列或独立发送任务。
- 加入临界区后，仿真中的异常暴露位置发生变化，但临界区本身不是随机停止的根因；它只是改变了指令布局和时序。

---

## 8. 运行一段时间后永久停止：中断断点错误

这是整个移植过程中最关键的问题。

### 8.1 初始现象

原 FreeRTOS bitstream 上板后能够输出 banner 和任务计数，但大约在 task1 到 50 后，串口不再更新。

“UART 忙时写会丢字符”无法解释永久停止，因此必须继续排查，不能停在第一个看似合理的原因上。

### 8.2 第一步：加长 RTL 仿真

把 `tb/tb_fpga_rtl.sv` 的调度后运行时间扩大到 2000000 周期，并要求：

```text
task1 >= 60
task2 >= 25
无同步异常
```

这样仿真可以覆盖板上约 50 tick 的停止区间，而不是只验证“任务曾经运行过”。

### 8.3 第二步：采样 CLINT 和 PC

一次失败采样中观察到：

```text
mtime    = 641573
mtimecmp = 216476
mip      = 0x00000080   # MTIP 已挂起
MIE      = 0            # 全局中断关闭
PC       = 0x0000016c
```

反汇编发现 `0x16c` 位于：

```text
freertos_risc_v_application_exception_handler + 0xc
j .
```

这说明 CPU 已进入异常处理死循环，而不是单纯等待 UART。

### 8.4 第三步：读取异常原因

捕获到：

```text
mcause = 0x00000004   # load address misaligned
mepc   = 0x00000e60
mtval  = 0xa5a5a5b1
```

反汇编 `mepc`：

```asm
lw a5, 12(s2)
```

当时 `s2` 本应保存 `xTasksWaitingTermination` 的合法地址，却变成了：

```text
0xA5A5A5A5
```

`0xA5` 是 FreeRTOS 的任务栈填充字节，因此：

```text
s2 + 12 = 0xA5A5A5A5 + 0xC = 0xA5A5A5B1
```

与 `mtval` 完全一致。

### 8.5 第四步：跟踪上下文保存和恢复

对 `s2` 的栈保存/恢复以及中断进入、mret 进行跟踪，发现关键序列：

```text
EX 当前指令：0x00000e4c  # ret
中断类型   ：0x80000007  # 机器定时器中断
保存 mepc  ：0x00000e50  # ret + 4
```

`ret` 前面的函数 epilogue 已经恢复了调用者寄存器并释放了栈帧。如果中断返回后从 `ret+4` 继续执行，就会直接落在函数中间，而不再执行函数 prologue，随后 `s2` 便以错误的 `0xA5A5A5A5` 参与地址计算。

### 8.6 真正根因

原逻辑把异步中断断点写成：

```systemverilog
id_valid_i ? id_pc_i : (pc_i + 4)
```

但当前 EX 指令在中断周期仍会提交。如果该指令是：

- `jal`；
- `jalr`，包括 `ret`；
- 实际发生的条件分支；

那么“下一条应执行的指令”就不是简单的 `pc+4`，而是实际跳转目标。

因此，这是一个**精确异常/中断断点问题**，不是 FreeRTOS 内核本身的问题。

### 8.7 RTL 修复

在 `rtl/ex_unit.sv` 中新增实际下一 PC 的选择：

```systemverilog
logic [31:0] irq_next_pc;

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

修复原则：

- 同步异常：保存当前异常指令 PC。
- 异步中断：当前 EX 指令仍提交，因此保存它之后的**实际执行地址**。
- 控制转移与中断同拍时，必须保存跳转目标。

### 8.8 回归与实现结果

修复后运行同一 200 万周期回归：

```text
task1: 1 → 68
task2: 0 → 33
无异常
==== FPGA-RTL TEST PASSED ====
```

最终 bitstream 实现结果：

```text
WNS = +7.149 ns
TNS = 0
失败端点 = 0
All user specified timing constraints are met.
```

对应文件：

```text
fpga/RISCV.runs/impl_1/riscv_board_freertos_irqfix.bit
```

烧录后，串口持续更新 task1/task2 计数，完成真实硬件验证。

---

## 9. 常用异常码速查

| mcause | 含义 | 本工程中的用途/案例 |
|---:|---|---|
| `0x00000004` | load 地址非对齐 | 错误中断返回后，`s2=A5A5A5A5` 导致 |
| `0x00000006` | store 地址非对齐 | 检查错误栈指针或数据指针 |
| `0x00000002` | 非法指令 | 检查取指、ROM 初始化、ISA 扩展 |
| `0x0000000B` | M 模式 ecall | FreeRTOS 主动请求任务切换 |
| `0x80000007` | 机器定时器中断 | CLINT 产生 FreeRTOS Tick |

判断方法：`mcause` 最高位为 1 通常表示异步中断；最高位为 0 表示同步异常。

---

## 10. 推荐复现与验证流程

### 10.1 构建固件

在工程根目录执行：

```powershell
.\freertos_app\build.ps1
```

确认输出：

```text
freertos_app/build/firmware.elf
freertos_app/build/firmware.hex
```

### 10.2 运行 RTL 仿真

使用：

```text
tb/tb_fpga_rtl.sv
```

重点不是只看调度器是否启动，而是检查：

- task1/task2 是否持续增长；
- 是否覆盖原故障发生的 Tick 区间；
- `g_probe[3]` 是否保持 0；
- 是否出现非预期同步异常；
- mtime/mtimecmp 是否持续推进。

### 10.3 更新正式 FPGA 镜像

```powershell
Copy-Item .\freertos_app\build\firmware.hex .\fpga\hex\firmware.hex -Force
```

注意不要混淆：

```text
freertos_app/build/firmware.hex  # 当前编译实验固件
fpga/hex/firmware.hex            # Vivado 正式构建实际读取的固件
```

### 10.4 构建 bitstream

```powershell
& "D:\vivado\2023.2\bin\vivado.bat" -mode batch -source ".\fpga\scripts\build.tcl"
```

构建后必须检查：

- bitstream 的修改时间是否更新；
- 时序报告 WNS/TNS；
- 构建日志是否 `BUILD ALL DONE`；
- 烧录文件是否确实是本次生成的新文件。

### 10.5 板级验收

串口选择 COM3、115200、8N1、文本模式，正常输出示例：

```text
==== FreeRTOS on RV32IM (3-stage) start ====
[task2] count=5
[task1] count=10
[task2] count=10
[task1] count=20
...
```

验收条件：

1. 不出现两个任务标签混杂在同一行；
2. count 持续增加，不停在原故障点附近；
3. 不出现 `ERROR: stack overflow` 或 `ERROR: malloc failed`；
4. task1 计数总体约为 task2 的两倍；
5. 连续运行 10～30 分钟仍稳定；
6. 按复位键后能重新启动。

---

## 11. 关键文件索引

| 文件 | 作用 |
|---|---|
| `freertos_app/FreeRTOSConfig.h` | 25 MHz、1 kHz Tick、堆栈、ISR 栈及内核裁剪 |
| `freertos_app/main.c` | 双任务、UART 原子日志、GPO、错误钩子 |
| `freertos_app/startup.S` | 复位入口、栈、bss/data 初始化 |
| `freertos_app/link.ld` | IMEM/DMEM 链接布局 |
| `freertos_app/build.ps1` | Windows xPack 固件构建 |
| `rtl/ex_unit.sv` | 最终中断断点修复位置 |
| `rtl/if_unit.sv` | 重定向优先于停顿 |
| `rtl/rf_unit.sv` | GPR、CSR、异常进入与 mret 状态 |
| `rtl/clint.sv` | mtime/mtimecmp 与 MTIP |
| `fpga/rtl/fpga_rom.sv` | 单异步读初始化 ROM |
| `fpga/rtl/riscv_soc_fpga.sv` | 双 ROM、DMEM/UART/GPO/CLINT 地址译码 |
| `fpga/rtl/riscv_board.sv` | MMCM、复位同步、板级接口 |
| `tb/tb_fpga_rtl.sv` | 长周期双任务及异常回归 |
| `fpga/scripts/build.tcl` | Vivado 全量构建脚本 |

---

## 12. 本次调试最重要的经验

1. **先证明底层链路，再调试 RTOS。** 时钟、LED、UART、裸机、取指均独立验证后，FreeRTOS 问题才有明确边界。
2. **“能运行一会儿”不等于移植完成。** 必须运行到超过历史故障点，并检查长期计数和异常状态。
3. **一个现象可能有多个根因。** 串口混杂来自任务竞态，永久停止来自中断断点错误，两者不能混为一谈。
4. **第一个合理解释不一定足以解释全部现象。** UART 忙时写能解释丢字符，却不能解释状态机永久不恢复。
5. **综合前 RTL 仿真通过不代表综合后硬件正确。** 双异步读初始化 ROM 的问题需要综合后仿真和板上诊断共同定位。
6. **异常现场比猜测更有价值。** `mcause/mepc/mtval/PC` 加反汇编，是定位随机死机的关键证据链。
7. **中断断点必须遵循指令提交语义。** 当前指令若提交，保存的应是实际下一 PC；遇到跳转和分支时不能固定使用 `pc+4`。
8. **固件版本必须与 bitstream 对应。** 实验 hex、正式 hex、已交付 bitstream 应明确区分，避免“改了源码但烧的是旧镜像”。
