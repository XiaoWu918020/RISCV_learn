#!/usr/bin/env python3
#==============================================================================
# File        : riscv_as.py
# Description : 迷你 RISC-V RV32IM 汇编器（教学/测试用）。
#               支持常用 RV32I + RV32M 指令、标签、符号分支偏移，
#               两遍扫描：第一遍收集标签地址，第二遍编码，输出 Verilog
#               $readmemh 可直接加载的 hex（每行一条 32 位指令）。
# Usage       : python riscv_as.py <input.s> <output.hex>
# 语法        : 一行一条指令；标签以冒号结尾；# 之后为注释；
#               支持 "imm(rs1)" 访存操作数；立即数支持十进制/0x 十六进制。
#==============================================================================
import sys

# 操作码
OP_LUI, OP_AUIPC = 0x37, 0x17
OP_JAL, OP_JALR = 0x6F, 0x67
OP_BRANCH, OP_LOAD, OP_STORE = 0x63, 0x03, 0x23
OP_OPIMM, OP_OP = 0x13, 0x33

# R 型整数指令：(funct7, funct3)
R_BASE = {
    "add": (0x00, 0), "sub": (0x20, 0),
    "sll": (0x00, 1), "slt": (0x00, 2), "sltu": (0x00, 3),
    "xor": (0x00, 4), "srl": (0x00, 5), "sra": (0x20, 5),
    "or":  (0x00, 6), "and": (0x00, 7),
}
# RV32M：funct7 固定 1，funct3 即子操作
R_M = {name: i for i, name in enumerate(
    ["mul", "mulh", "mulhsu", "mulhu", "div", "divu", "rem", "remu"])}
# I 型运算（OPIMM）：funct3，移位类单独处理 funct7
I_ALU = {
    "addi": 0, "slti": 2, "sltiu": 3, "xori": 4, "ori": 6, "andi": 7,
    "slli": 1, "srli": 5, "srai": 5,
}
# load：funct3
LOADS = {"lb": 0, "lh": 1, "lw": 2, "lbu": 4, "lhu": 5}
# store：funct3
STORES = {"sb": 0, "sh": 1, "sw": 2}
# branch：funct3
BRANCHS = {"beq": 0, "bne": 1, "blt": 4, "bge": 5, "bltu": 6, "bgeu": 7}

# SYSTEM 操作码
OP_SYSTEM = 0x73

# CSR 名称 -> 地址（测试程序可用名称，也可直接写数字地址）
CSR_NAMES = {
    "mvendorid": 0xF11, "marchid": 0xF12, "mimpid": 0xF13, "mhartid": 0xF14,
    "mstatus": 0x300, "misa": 0x301, "mie": 0x304, "mtvec": 0x305,
    "mscratch": 0x306, "mepc": 0x341, "mcause": 0x342, "mtval": 0x343,
    "mip": 0x344, "mcycle": 0xB00, "minstret": 0xB02,
    "cycle": 0xC00, "instret": 0xC02,
}

# CSR 寄存器源指令：funct3
CSR_REG = {"csrrw": 1, "csrrs": 2, "csrrc": 3}
# CSR 立即数源指令：funct3（源字段为零扩展的 5 位 uimm）
CSR_IMM = {"csrrwi": 5, "csrrsi": 6, "csrrci": 7}


def parse_csr(tok):
    """解析 CSR 名称或数字地址"""
    tok = tok.strip()
    if tok.lower() in CSR_NAMES:
        return CSR_NAMES[tok.lower()]
    return parse_imm(tok)


def enc_csr(csr, src, rd, f3):
    """编码 CSR 指令（src 为 rs1 寄存器号或 uimm，复用同一字段）"""
    return ((csr << 20) | (src << 15) | (f3 << 12) | (rd << 7) | OP_SYSTEM)


def parse_reg(tok):
    """解析寄存器名 x0..x31"""
    tok = tok.strip()
    if not (tok.startswith("x") and tok[1:].isdigit()):
        raise ValueError(f"非法寄存器: {tok}")
    idx = int(tok[1:])
    if not 0 <= idx <= 31:
        raise ValueError(f"寄存器越界: {tok}")
    return idx


def parse_imm(tok):
    """解析十进制/十六进制立即数（可负）"""
    tok = tok.strip()
    return int(tok, 16) if tok.lower().startswith("0x") else int(tok, 10)


def to_signed_imm(value, width):
    """截断到 width 位并校验范围"""
    lo, hi = -(1 << (width - 1)), (1 << (width - 1)) - 1
    if not lo <= value <= hi:
        raise ValueError(f"立即数 {value} 超出 {width} 位范围")
    return value & ((1 << width) - 1)


def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return ((funct7 << 25) | (rs2 << 20) | (rs1 << 15) |
            (funct3 << 12) | (rd << 7) | opcode)


def enc_i(imm, rs1, funct3, rd, opcode):
    return ((to_signed_imm(imm, 12) << 20) | (rs1 << 15) |
            (funct3 << 12) | (rd << 7) | opcode)


def enc_s(imm, rs2, rs1, funct3, opcode):
    v = to_signed_imm(imm, 12)
    return (((v >> 5) << 25) | (rs2 << 20) | (rs1 << 15) |
            (funct3 << 12) | ((v & 0x1F) << 7) | opcode)


def enc_b(imm, rs2, rs1, funct3, opcode):
    v = to_signed_imm(imm, 13)
    return ((((v >> 12) & 1) << 31) | (((v >> 5) & 0x3F) << 25) |
            (rs2 << 20) | (rs1 << 15) | (funct3 << 12) |
            (((v >> 1) & 0xF) << 8) | (((v >> 11) & 1) << 7) | opcode)


def enc_u(imm, rd, opcode):
    return ((imm & 0xFFFFF000) | (rd << 7) | opcode)


def enc_j(imm, rd, opcode):
    v = to_signed_imm(imm, 21)
    return ((((v >> 20) & 1) << 31) | (((v >> 1) & 0x3FF) << 21) |
            (((v >> 11) & 1) << 20) | (((v >> 12) & 0xFF) << 12) |
            (rd << 7) | opcode)


def split_mem(tok):
    """解析 imm(rs1) -> (imm, rs1)"""
    tok = tok.strip()
    base = tok.index("(")
    if not tok.endswith(")"):
        raise ValueError(f"非法访存操作数: {tok}")
    return parse_imm(tok[:base]), parse_reg(tok[base + 1:-1])


def preprocess(path):
    """读入并去除注释/空白，返回 (标签或指令) 行列表"""
    lines = []
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.split("#", 1)[0].strip()
            if line:
                lines.append(line)
    return lines


def assemble(path):
    lines = preprocess(path)

    # 第一遍：收集标签 -> 字节地址（la 伪指令展开为 2 条指令，占 8 字节）
    labels, pc = {}, 0
    for line in lines:
        if line.endswith(":"):
            labels[line[:-1].strip()] = pc
        else:
            mn = line.replace(",", " ").split()[0].lower()
            pc += 8 if mn == "la" else 4

    # 第二遍：编码
    out, pc = [], 0
    for line in lines:
        if line.endswith(":"):
            continue
        parts = line.replace(",", " ").split()
        m, ops = parts[0].lower(), parts[1:]

        if m in R_BASE:
            f7, f3 = R_BASE[m]
            out.append(enc_r(f7, parse_reg(ops[2]), parse_reg(ops[1]),
                             f3, parse_reg(ops[0]), OP_OP))
        elif m in R_M:
            out.append(enc_r(1, parse_reg(ops[2]), parse_reg(ops[1]),
                             R_M[m], parse_reg(ops[0]), OP_OP))
        elif m in I_ALU:
            f3 = I_ALU[m]
            f7 = 0x20 if m == "srai" else 0x00
            if m in ("slli", "srli", "srai"):
                sh = to_signed_imm(parse_imm(ops[2]), 5)
                out.append(enc_r(f7, sh, parse_reg(ops[1]), f3,
                                 parse_reg(ops[0]), OP_OP))
            else:
                out.append(enc_i(parse_imm(ops[2]), parse_reg(ops[1]),
                                 f3, parse_reg(ops[0]), OP_OPIMM))
        elif m in LOADS:
            imm, rs1 = split_mem(ops[1])
            out.append(enc_i(imm, rs1, LOADS[m], parse_reg(ops[0]), OP_LOAD))
        elif m in STORES:
            imm, rs1 = split_mem(ops[1])
            out.append(enc_s(imm, parse_reg(ops[0]), rs1,
                             STORES[m], OP_STORE))
        elif m in BRANCHS:
            target = labels[ops[2]]
            out.append(enc_b(target - pc, parse_reg(ops[1]),
                             parse_reg(ops[0]), BRANCHS[m], OP_BRANCH))
        elif m == "lui":
            out.append(enc_u(parse_imm(ops[1]) & 0xFFFFF000,
                             parse_reg(ops[0]), OP_LUI))
        elif m == "auipc":
            out.append(enc_u(parse_imm(ops[1]) & 0xFFFFF000,
                             parse_reg(ops[0]), OP_AUIPC))
        elif m == "jal":
            out.append(enc_j(labels[ops[1]] - pc, parse_reg(ops[0]), OP_JAL))
        elif m == "jalr":
            # 兼容 "jalr rd, imm(rs1)" 与 "jalr rd, rs1, imm" 两种写法
            if "(" in ops[1]:
                imm, rs1 = split_mem(ops[1])
            else:
                rs1, imm = parse_reg(ops[1]), parse_imm(ops[2])
            out.append(enc_i(imm, rs1, 0, parse_reg(ops[0]), OP_JALR))
        elif m in CSR_REG:
            # csrrw/csrrs/csrrc rd, csr, rs1
            out.append(enc_csr(parse_csr(ops[1]), parse_reg(ops[2]),
                               parse_reg(ops[0]), CSR_REG[m]))
        elif m in CSR_IMM:
            # csrrwi/csrrsi/csrrrci rd, csr, uimm
            out.append(enc_csr(parse_csr(ops[1]), parse_imm(ops[2]),
                               parse_reg(ops[0]), CSR_IMM[m]))
        elif m == "csrr":
            # 伪指令 csrr rd, csr -> csrrs rd, csr, x0
            out.append(enc_csr(parse_csr(ops[1]), 0, parse_reg(ops[0]), 2))
        elif m == "csrw":
            # 伪指令 csrw csr, rs -> csrrw x0, csr, rs
            out.append(enc_csr(parse_csr(ops[0]), parse_reg(ops[1]), 0, 1))
        elif m == "csrwi":
            # 伪指令 csrwi csr, uimm -> csrrwi x0, csr, uimm
            out.append(enc_csr(parse_csr(ops[0]), parse_imm(ops[1]), 0, 5))
        elif m == "ecall":
            out.append(0x00000073)
        elif m == "ebreak":
            out.append(0x00100073)
        elif m == "mret":
            out.append(0x30200073)
        elif m == "la":
            # 伪指令 la rd, label -> auipc rd, hi20 ; addi rd, rd, lo12
            rd_la = parse_reg(ops[0])
            rel = labels[ops[1]] - pc                       # 相对 auipc 的偏移
            hi = (rel + 0x800) & 0xFFFFF000                # 高 20 位字段
            lo = rel & 0xFFF                               # 低 12 位字段
            out.append((hi & 0xFFFFF000) | (rd_la << 7) | OP_AUIPC)
            out.append((lo << 20) | (rd_la << 15) | (rd_la << 7) | OP_OPIMM)
            pc += 4                                        # 多占一条指令
        else:
            raise ValueError(f"不支持的指令: {m}  ({line})")
        pc += 4

    return out


def main():
    if len(sys.argv) != 3:
        sys.exit("Usage: python riscv_as.py <input.s> <output.hex>")
    words = assemble(sys.argv[1])
    with open(sys.argv[2], "w", encoding="utf-8", newline="\n") as f:
        for w in words:
            f.write(f"{w:08x}\n")
    print(f"Assembled {len(words)} instructions -> {sys.argv[2]}")


if __name__ == "__main__":
    main()
