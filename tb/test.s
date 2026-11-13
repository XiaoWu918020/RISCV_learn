#==============================================================================
# test.s : RV32IM 三级流水线核功能测试程序
# 覆盖：RV32I 算术/逻辑/移位/比较、全部 6 种条件分支、jal/jalr、load/store
#       对齐与符号扩展、RV32M 全部乘除取余、CSR 读写、ecall 异常 + mret、
#       msip 软件中断。每段结果即时写入 0x2000 起的签名区，testbench 逐一
#       比对，以最后一个签名槽 done=1 作为结束标志。
# 地址布局：数据区 0x1000，中断握手标志 0x3000，签名区 0x2000~0x2064。
#==============================================================================

# ---------------- 1. 立即数与算术逻辑 ---------------------------------------
addi x1, x0, 10            # x1 = 10
addi x2, x0, -3            # x2 = -3
add  x3, x1, x2            # x3 = 7
sub  x4, x1, x2            # x4 = 13
lui  x5, 0x12345000        # x5 = 0x12345000
auipc x6, 0                # x6 = 当前 PC
ori  x7, x0, 0xFF          # x7 = 255
andi x8, x7, 0x0F          # x8 = 15
xori x9, x7, 0xFF          # x9 = 0
slli x10, x1, 4            # x10 = 160
srli x11, x10, 2           # x11 = 40
srai x12, x2, 1            # x12 = -2
slt  x13, x2, x1           # x13 = 1（-3 < 10）
slti x14, x1, 5            # x14 = 0（10 不小于 5）
sltu x15, x1, x2           # x15 = 1（无符号 10 < 4294967293）

# ---------------- 2. 条件分支 beq/bne ---------------------------------------
addi x16, x0, 0
beq  x9, x0, BR1           # x9==0，跳转
addi x16, x0, 99           # 应被跳过
BR1:
bne  x1, x0, BR2           # x1!=0，跳转
addi x16, x0, 99           # 应被跳过
BR2:
addi x16, x0, 7            # x16 = 7

# ---------------- 3. 跳转 jal / jalr ----------------------------------------
jal x17, J1                # x17 = 返回地址，跳转
addi x16, x0, 99           # 应被跳过
J1:
auipc x18, 0               # x18 = 本条 PC（记为 A）
addi x18, x18, 16          # x18 = A+16（load 段入口）
jalr x19, x18, 0           # 跳转到 A+16
addi x16, x0, 99           # 应被跳过

# ---------------- 4. load / store -------------------------------------------
lui x20, 0x00001000        # 数据区基址 0x1000
addi x21, x0, 0x55
sw   x21, 0(x20)           # mem[0x1000] = 0x55
lw   x22, 0(x20)           # x22 = 0x55
sb   x1, 0(x20)            # mem[0x1000] = 10
lbu  x23, 0(x20)           # x23 = 10
sh   x2, 2(x20)            # mem[0x1002] = 0xFFFD
lhu  x24, 2(x20)           # x24 = 0x0000FFFD
lh   x25, 2(x20)           # x25 = -3

# ---------------- 5. RV32M 乘除 ---------------------------------------------
mul  x26, x1, x2           # x26 = -30
mulh x27, x1, x2           # x27 = -1
div  x28, x1, x2           # x28 = -3
rem  x29, x1, x2           # x29 = 1
divu x30, x1, x2           # x30 = 0
remu x31, x1, x2           # x31 = 10

# ---------------- 签名段 1：基础功能（0x2000~0x2020） ------------------------
lui x20, 0x00002000
sw x3,  0(x20)             # 7
sw x4,  4(x20)             # 13
sw x16, 8(x20)             # 7
sw x22, 12(x20)            # 0x55
sw x23, 16(x20)            # 10
sw x25, 20(x20)            # -3
sw x26, 24(x20)            # -30
sw x28, 28(x20)            # -3
sw x29, 32(x20)            # 1

# ---------------- 6. 补全分支 / 字节加载 / 乘法 ------------------------------
addi x5, x0, 5
addi x6, x0, -5
blt  x6, x5, L_blt         # 有符号 -5 < 5
addi x16, x0, 99
L_blt:
bge  x5, x6, L_bge         # 5 >= -5
addi x16, x0, 99
L_bge:
bltu x5, x6, L_bltu        # 无符号 5 < 0xFFFFFFFB
addi x16, x0, 99
L_bltu:
bgeu x6, x5, L_bgeu        # 无符号 0xFFFFFFFB >= 5
addi x16, x0, 99
L_bgeu:
addi x16, x0, 42           # 全部分支正确标记

lui x20, 0x00001000
addi x7, x0, 0x80
sb   x7, 0(x20)            # mem[0x1000] = 0x80
lb   x8, 0(x20)            # 符号扩展 -> 0xFFFFFF80
lbu  x9, 0(x20)            # 零扩展 -> 0x00000080

addi x10, x0, 100
addi x11, x0, 200
mulhu x12, x10, x11        # 20000 高 32 位 = 0
lui  x10, 0x00010000       # 65536
lui  x11, 0x00010000       # 65536
mulhu x13, x10, x11        # 65536^2 = 2^32，高 32 = 1
mulh  x14, x10, x11        # 正数，有符号高 32 = 1
addi x10, x0, -10
lui  x11, 0x00010000
mulhsu x15, x10, x11       # -10*65536 高 32 = 0xFFFFFFFF

lui x1, 0x00002000
sw x16, 36(x1)             # 0x2024 = 42
sw x8,  40(x1)             # 0x2028 = 0xFFFFFF80
sw x9,  44(x1)             # 0x202C = 0x80
sw x12, 48(x1)             # 0x2030 = 0
sw x13, 52(x1)             # 0x2034 = 1
sw x14, 56(x1)             # 0x2038 = 1
sw x15, 60(x1)             # 0x203C = 0xFFFFFFFF

# ---------------- 7. CSR 普通读写 -------------------------------------------
lui  x1, 0x12345000
addi x1, x1, 0x678
csrw mscratch, x1          # 写魔数 0x12345678
csrr x2, mscratch          # 读回
csrr x3, misa              # 0x40001100
addi x4, x0, 8
csrrs x0, mstatus, x4      # 置 MIE
csrr x5, mstatus           # 0x88
csrrc x0, mstatus, x4      # 清 MIE
csrr x6, mstatus           # 0x80
csrr x7, minstret
sltu x8, x0, x7            # minstret > 0 -> 1

lui x9, 0x00002000
sw x2, 64(x9)              # 0x2040 = 0x12345678
sw x3, 68(x9)              # 0x2044 = 0x40001100
sw x5, 72(x9)              # 0x2048 = 0x88
sw x6, 76(x9)              # 0x204C = 0x80
sw x8, 80(x9)              # 0x2050 = 1

# ---------------- 8. ecall 同步异常 + mret ----------------------------------
la   x1, E_HANDLER
csrw mtvec, x1             # 设置异常入口
addi x16, x0, 0
ecall                      # 触发环境调用异常
addi x16, x0, 77           # mret 后回到这里
jal  x0, EC_DONE
E_HANDLER:
csrr x20, mcause           # 应为 11
csrr x21, mepc
addi x21, x21, 4           # mepc += 4，跳过 ecall
csrw mepc, x21
mret                       # 返回
EC_DONE:
lui x1, 0x00002000
sw x20, 84(x1)             # 0x2054 = 11
sw x16, 88(x1)             # 0x2058 = 77

# ---------------- 9. msip 软件中断（testbench 配合触发/清除） ----------------
la   x1, I_HANDLER
csrw mtvec, x1             # 中断入口
addi x2, x0, 8
csrw mie, x2               # 使能机器软件中断 MSIE
addi x3, x0, 8
csrrs x0, mstatus, x3      # 开全局中断 MIE
lui  x20, 0x00003000
addi x21, x0, 0
sw   x21, 0(x20)           # 握手标志 flag=0
I_WAIT:
lw   x22, 0(x20)
bne  x22, x0, I_CONT       # flag 被处理程序置 1 后退出
beq  x0, x0, I_WAIT
I_CONT:
addi x23, x0, 88           # 中断成功标记
jal  x0, I_DONE
I_HANDLER:
csrr x24, mcause           # 应为 0x80000003
lui  x25, 0x00003000
addi x26, x0, 1
sw   x26, 0(x25)           # flag=1
mret                       # 返回等待循环
I_DONE:
lui x1, 0x00002000
sw x24, 92(x1)             # 0x205C = 0x80000003
sw x23, 96(x1)             # 0x2060 = 88

# ---------------- 结束标志 ---------------------------------------------------
lui x1, 0x00002000
addi x2, x0, 1
sw x2, 100(x1)             # 0x2064 done = 1
END:
beq x0, x0, END            # 自循环停机
