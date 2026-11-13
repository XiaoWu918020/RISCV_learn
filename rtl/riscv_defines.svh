//==============================================================================
// File        : riscv_defines.svh
// Description : RISC-V RV32IM 三级流水线核公共定义（package）
//               集中管理指令操作码、ALU 操作编码、立即数类型、CSR 地址、
//               异常/中断原因码等全局常量，各模块通过 import 引用。
// Note        : 本文件为 package，需在其他模块之前优先编译。
//==============================================================================
package riscv_defines;

    //--------------------------------------------------------------------------
    // 通用位宽
    //--------------------------------------------------------------------------
    localparam logic [31:0] XLEN        = 32;   // 数据位宽
    localparam logic [31:0] REG_AW      = 5;    // 寄存器索引位宽
    localparam logic [31:0] REG_NUM     = 32;   // 通用寄存器数量
    localparam logic [31:0] INST_NOP    = 32'h0000_0013; // addi x0, x0, 0（气泡）

    //--------------------------------------------------------------------------
    // RISC-V 指令操作码 opcode[6:0]
    //--------------------------------------------------------------------------
    localparam logic [6:0] OP_LUI       = 7'b0110111; // U 型：lui
    localparam logic [6:0] OP_AUIPC     = 7'b0010111; // U 型：auipc
    localparam logic [6:0] OP_JAL       = 7'b1101111; // J 型：jal
    localparam logic [6:0] OP_JALR      = 7'b1100111; // I 型：jalr
    localparam logic [6:0] OP_BRANCH    = 7'b1100011; // B 型：条件分支
    localparam logic [6:0] OP_LOAD      = 7'b0000011; // I 型：加载
    localparam logic [6:0] OP_STORE     = 7'b0100011; // S 型：存储
    localparam logic [6:0] OP_OPIMM     = 7'b0010011; // I 型：寄存器-立即数运算
    localparam logic [6:0] OP_OP        = 7'b0110011; // R 型：寄存器-寄存器运算（含 M 扩展）
    localparam logic [6:0] OP_SYSTEM    = 7'b1110011; // I 型：CSR / ecall / ebreak / mret
    localparam logic [6:0] OP_MISCMEM   = 7'b0001111; // fence 类（本核按 NOP 处理）

    // funct7：M 扩展标识
    localparam logic [6:0] F7_M_EXT     = 7'b0000001;

    //--------------------------------------------------------------------------
    // ALU 操作编码（alu_op）
    //--------------------------------------------------------------------------
    localparam logic [4:0] ALU_ADD      = 5'd0;
    localparam logic [4:0] ALU_SUB      = 5'd1;
    localparam logic [4:0] ALU_SLL      = 5'd2;   // 逻辑左移
    localparam logic [4:0] ALU_SLT      = 5'd3;   // 有符号比较小于
    localparam logic [4:0] ALU_SLTU     = 5'd4;   // 无符号比较小于
    localparam logic [4:0] ALU_XOR      = 5'd5;
    localparam logic [4:0] ALU_SRL      = 5'd6;   // 逻辑右移
    localparam logic [4:0] ALU_SRA      = 5'd7;   // 算术右移
    localparam logic [4:0] ALU_OR       = 5'd8;
    localparam logic [4:0] ALU_AND      = 5'd9;

    //--------------------------------------------------------------------------
    // 立即数类型编码（imm_sel）
    //--------------------------------------------------------------------------
    localparam logic [2:0] IMM_X        = 3'd0;   // 无立即数
    localparam logic [2:0] IMM_I        = 3'd1;
    localparam logic [2:0] IMM_S        = 3'd2;
    localparam logic [2:0] IMM_B        = 3'd3;
    localparam logic [2:0] IMM_U        = 3'd4;
    localparam logic [2:0] IMM_J        = 3'd5;

    //--------------------------------------------------------------------------
    // 访存大小编码（funct3[1:0]）
    //--------------------------------------------------------------------------
    localparam logic [1:0] MEM_BYTE     = 2'b00;  // 1 字节
    localparam logic [1:0] MEM_HALF     = 2'b01;  // 2 字节
    localparam logic [1:0] MEM_WORD     = 2'b10;  // 4 字节

    //--------------------------------------------------------------------------
    // CSR 操作类型（csr_op）
    //--------------------------------------------------------------------------
    localparam logic [1:0] CSR_NONE     = 2'd0;   // 非 CSR 指令
    localparam logic [1:0] CSR_RW       = 2'd1;   // csrrw / csrrwi
    localparam logic [1:0] CSR_RS       = 2'd2;   // csrrs / csrrsi
    localparam logic [1:0] CSR_RC       = 2'd3;   // csrrc / csrrci

    //--------------------------------------------------------------------------
    // CSR 寄存器地址
    //--------------------------------------------------------------------------
    localparam logic [11:0] CSR_MVENDORID = 12'hF11;
    localparam logic [11:0] CSR_MARCHID   = 12'hF12;
    localparam logic [11:0] CSR_MIMPID    = 12'hF13;
    localparam logic [11:0] CSR_MHARTID   = 12'hF14;
    localparam logic [11:0] CSR_MSTATUS   = 12'h300;
    localparam logic [11:0] CSR_MISA      = 12'h301;
    localparam logic [11:0] CSR_MIE       = 12'h304;
    localparam logic [11:0] CSR_MTVEC     = 12'h305;
    localparam logic [11:0] CSR_MSCRATCH  = 12'h306;
    localparam logic [11:0] CSR_MEPC      = 12'h341;
    localparam logic [11:0] CSR_MCAUSE    = 12'h342;
    localparam logic [11:0] CSR_MTVAL     = 12'h343;
    localparam logic [11:0] CSR_MIP       = 12'h344;
    localparam logic [11:0] CSR_MCYCLE    = 12'hB00;
    localparam logic [11:0] CSR_MINSTRET  = 12'hB02;
    localparam logic [11:0] CSR_CYCLE     = 12'hC00;
    localparam logic [11:0] CSR_INSTRET   = 12'hC02;

    // mstatus 位定义（仅实现 M 模式必需的 MIE/MPIE）
    localparam logic [31:0] M_STATUS_MIE  = 3;
    localparam logic [31:0] M_STATUS_MPIE = 7;

    // mie / mip 位定义
    localparam logic [31:0] M_INT_MS      = 3;    // 机器软件中断
    localparam logic [31:0] M_INT_MT      = 7;    // 机器定时器中断
    localparam logic [31:0] M_INT_ME      = 11;   // 机器外部中断

    //--------------------------------------------------------------------------
    // mcause 编码（最高位为中断/异常标识）
    //--------------------------------------------------------------------------
    localparam logic [31:0] CAUSE_INST_MISALIGN = 32'd0;  // 指令地址非对齐
    localparam logic [31:0] CAUSE_ILLEGAL_INST  = 32'd2;  // 非法指令
    localparam logic [31:0] CAUSE_BREAKPOINT    = 32'd3;  // 断点 ebreak
    localparam logic [31:0] CAUSE_LOAD_MISALIGN = 32'd4;  // 加载地址非对齐
    localparam logic [31:0] CAUSE_STORE_MISALIGN= 32'd6;  // 存储地址非对齐
    localparam logic [31:0] CAUSE_ECALL_M       = 32'd11; // M 模式 ecall
    localparam logic [31:0] CAUSE_S_INT         = 32'h8000_0003; // 软件中断
    localparam logic [31:0] CAUSE_T_INT         = 32'h8000_0007; // 定时器中断
    localparam logic [31:0] CAUSE_E_INT         = 32'h8000_000B; // 外部中断

    // 注：打包控制类型 ctrl_bus_t 定义在 rtl/riscv_types.svh（全局 include）

endpackage
