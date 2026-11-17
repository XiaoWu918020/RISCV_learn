#==============================================================================
# timer.s : 裸机验证 sw/lw 配置 mtimecmp 并进入机器定时器中断
# 流程    : 设置 mtvec -> 读 mtime 计算目标 -> 安全写 mtimecmp -> 使能 MTIE/MIE
#           -> 等待中断；处理程序记录 mcause、置标志、推远 mtimecmp 后 mret。
# 地址    : CLINT=0x40000000 (MSIP +0x0000, MTIMECMP +0x4000, MTIME +0xBFF8)
#           DMEM =0x20000000 (hit +0, mcause +4, done +8)
#==============================================================================

# ---------------- 1. 设置中断向量 --------------------------------------------
la x1, TMR_HANDLER          # x1 = 处理程序地址
csrw mtvec, x1              # mtvec = TMR_HANDLER

# ---------------- 2. CLINT 各部件地址 ----------------------------------------
lui x6, 0x40000000          # x6 = CLINT base（MSIP）
lui x7, 0x40004000          # x7 = MTIMECMP base 0x40004000
lui x8, 0x4000c000          # x8 = 0x4000C000
addi x8, x8, -8             # x8 = 0x4000BFF8（MTIME base）

# ---------------- 3. mtimecmp 高先写全 1，防止配置期间误触发 -----------------
lui x10, 0xfffff000
addi x10, x10, -1           # x10 = 0xFFFFFFFF
sw x10, 4(x7)               # mtimecmph = 0xFFFFFFFF

# ---------------- 4. 读当前 mtime --------------------------------------------
lw x11, 0(x8)               # mtimel
lw x12, 4(x8)               # mtimeh

# ---------------- 5. 目标 = mtime + 200（处理低 32 位进位）------------------
addi x13, x11, 200          # target low
sltu x18, x13, x11          # 加 200 回绕则 x18 = 1
beq x18, x0, NO_CARRY
addi x12, x12, 1            # 回绕：target high + 1
NO_CARRY:

# ---------------- 6. 写 mtimecmp（先低后高，最后写高才真正生效）-------------
sw x13, 0(x7)               # mtimecmpl
sw x12, 4(x7)               # mtimecmph

# ---------------- 7. 使能定时器中断与全局中断 --------------------------------
addi x14, x0, 128           # 0x80 = mie.MTIE（bit7）
csrw mie, x14
addi x15, x0, 8             # 0x08 = mstatus.MIE（bit3）
csrrs x0, mstatus, x15

# ---------------- 8. 主循环等待处理程序置位 hit ------------------------------
lui x9, 0x20000000          # DMEM base
WAIT:
lw x16, 0(x9)               # 轮询 hit
bne x16, x0, GOT_IT         # hit != 0 表示已进过定时器中断
beq x0, x0, WAIT
GOT_IT:
addi x17, x0, 1
sw x17, 8(x9)               # done = 1
END:
beq x0, x0, END             # 自循环停机

# ---------------- 定时器中断处理程序 -----------------------------------------
TMR_HANDLER:
csrr x20, mcause            # 期望 0x80000007（机器定时器中断）
lui x9, 0x20000000
addi x21, x0, 1
sw x21, 0(x9)               # hit = 1
sw x20, 4(x9)               # 记录 mcause
lui x22, 0x40004000
lui x23, 0xfffff000
addi x23, x23, -1
sw x23, 4(x22)              # mtimecmph = 全1，避免 mret 后反复触发
mret                        # 返回等待循环
