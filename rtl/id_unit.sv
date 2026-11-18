//==============================================================================
// File        : id_unit.sv
// Module      : id_unit —— 二级流水线：译码单元（ID）
// Description : 对应框图 ID_UNIT，内部包含：
//                 (1) id     ：组合译码器 + 立即数生成，输出打包控制总线
//                 (2) id_ex  ：ID -> EX 流水线寄存器
//               同时完成：
//                 - EX -> ID 数据转发（解决大部分数据相关，零停顿）
//                 - load-use / CSR 写后读冒险检测（停顿一拍并注入气泡）
//               完整支持 RV32I 基础整数指令与 RV32M 乘除指令译码。
//==============================================================================
//=====================RISCV六类指令格式表（译码参考）============================
//1. R 型：OP-OP（寄存器-寄存器运算）
//   [31 : 25] [24 : 20] [19 : 15] [14 : 12] [11 : 7] [6 : 0]
//    funct7      rs2       rs1     funct3      rd    opcode
//2. I 型：OP-IMM（寄存器-立即数运算）、LOAD、JALR、CSR 指令
//   [31 : 20] [19 : 15] [14 : 12] [11 : 7] [6 : 0]
//    imm[11:0]   rs1     funct3      rd    opcode
//
//   对整个指令来看，imm[11:0] = inst[31:20]
//   符号扩展后为 imm[31:0] = {{20{inst[31]}}, inst[31:20]}
//3. S 型：STORE
//   [31 : 25] [24 : 20] [19 : 15] [14 : 12] [11 : 7] [6 : 0]
//   imm[11:5]    rs2       rs1     funct3   imm[4:0] opcode
//
//   对整个指令来看，imm[11:0] = { inst[31:25], inst[11:7] }
//   符号扩展后为 imm[31:0] = {{20{inst[31]}}, inst[31:25], inst[11:7]}
//4. B 型：BRANCH
//   [31 : 25] [24 : 20] [19 : 15] [14 : 12] [11 : 7] [6 : 0]
//   imm[12|10:5]  rs2      rs1     funct3   imm[4:1|11]  opcode
//   
//   完整立即数imm[12:0] = { imm[12], imm[11], imm[10:5], imm[4:1], 1'b0 }
//   对整个指令来看，imm[12:0] = { inst[31], inst[7], inst[30:25], inst[11:8], 1'b0 }
//   符号扩展后为 imm[31:0] = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
//5. U 型：LUI、AUIPC 
//   [31 : 12]      [11 : 7]           [6 : 0]
//   imm[31:12]        rd              opcode
//
//   立即数imm[31:0] = { inst[31:12], 12'b0 }，直接左移 12 位扩展
//6. J 型：JAL
//   [31 : 12]                  [11 : 7]       [6 : 0]
//   imm[20|10:1|11|19:12]         rd          opcode
//
//   完整立即数imm[20:0] = { imm[20], imm[10:1], imm[11], imm[19:12], 1'b0 }
//   对整个指令来看，imm[20:0] = { inst[31], inst[19:12], inst[20], inst[30:21], 1'b0 }
//   符号扩展后为 imm[31:0] = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
//==============================================================================
//   各类型指令的立即数组成看似乱七八糟，实则是为了最大程度复用译码逻辑
//==============================================================================
`include "riscv_types.svh"
module id_unit (
    input  logic        clk,
    input  logic        rst_n,

    // 来自 IF/ID 寄存器
    input  logic [31:0] ifid_pc_i,
    input  logic [31:0] ifid_inst_i,
    input  logic        ifid_valid_i,

    // 执行级重定向冲刷（分支/跳转/异常/中断/mret）
    input  logic        flush_i,

    // 通用寄存器堆读出数据
    input  logic [31:0] gpr_a_i,          // rs1 读出值
    input  logic [31:0] gpr_b_i,          // rs2 读出值

    // 执行级（EX）信息——用于转发与冒险检测
    input  logic        ex_wreg_i,        // EX 指令 GPR 写回使能
    input  logic [4:0]  ex_rd_i,          // EX 指令目的寄存器
    input  logic [31:0] ex_wdata_i,       // EX 指令写回数据
    input  logic        ex_mem_read_i,    // EX 指令是否为 load
    input  logic        ex_csr_we_i,      // EX 指令是否在写 CSR
    input  logic [11:0] ex_csr_addr_i,    // EX 指令所写 CSR 地址

    // 寄存器堆读地址
    output logic [4:0]  rs1_addr_o,
    output logic [4:0]  rs2_addr_o,

    // 流水线停顿请求（load-use / CSR 相关）
    output logic        stall_o,

    // ID/EX 寄存器输出（送往 ex_unit）
    output logic [31:0] idex_pc_o,        // 指令 PC
    output logic        idex_valid_o,     // 有效位
    output ctrl_bus_t   idex_ctrl_o,      // 打包控制字段
    output logic [4:0]  idex_rs1_o,
    output logic [4:0]  idex_rs2_o,
    output logic [4:0]  idex_rd_o,
    output logic [31:0] idex_reg_a_o,     // 转发后的操作数 A
    output logic [31:0] idex_reg_b_o,     // 转发后的操作数 B（含 store 数据）
    output logic [31:0] idex_imm_o,       // 符号扩展立即数
    output logic [31:0] idex_inst_o       // 原始指令（调试/ mtval 用）
);

    import riscv_defines::*;

    //--------------------------------------------------------------------------
    // 指令字段拆解
    //--------------------------------------------------------------------------
    logic [6:0] opcode;
    logic [4:0] rs1, rs2, rd;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = ifid_inst_i[6:0];
    assign rd     = ifid_inst_i[11:7];
    assign funct3 = ifid_inst_i[14:12];
    assign rs1    = ifid_inst_i[19:15];
    assign rs2    = ifid_inst_i[24:20];
    assign funct7 = ifid_inst_i[31:25];

    assign rs1_addr_o = rs1;
    assign rs2_addr_o = rs2;

    //--------------------------------------------------------------------------
    // 组合译码器：生成控制总线 ctrl_d
    //--------------------------------------------------------------------------
    ctrl_bus_t ctrl_d;

    always_comb begin
        // 默认值：全部清零（即 NOP / 无写回），illegal 单独置位
        ctrl_d = '0;

        if (!ifid_valid_i) begin
            // 气泡：保持默认空控制
            ctrl_d = '0;
        end else begin
            unique case (opcode)
                //--------------------------------------------------------------
                // LUI：rd = imm(U)
                //--------------------------------------------------------------
                OP_LUI: begin
                    ctrl_d.imm_sel   = IMM_U;
                    ctrl_d.lui       = 1'b1;
                    ctrl_d.reg_write = 1'b1;
                end

                //--------------------------------------------------------------
                // AUIPC：rd = PC + imm(U)
                //--------------------------------------------------------------
                OP_AUIPC: begin
                    ctrl_d.imm_sel   = IMM_U;
                    ctrl_d.auipc     = 1'b1;
                    ctrl_d.alu_src   = 1'b1;   // ALU B 选 U 型立即数
                    ctrl_d.alu_op    = ALU_ADD;
                    ctrl_d.reg_write = 1'b1;
                end

                //--------------------------------------------------------------
                // JAL：rd = PC+4，PC = PC + imm(J)
                //--------------------------------------------------------------
                OP_JAL: begin
                    ctrl_d.imm_sel   = IMM_J;
                    ctrl_d.jump      = 1'b1;
                    ctrl_d.reg_write = 1'b1;
                end

                //--------------------------------------------------------------
                // JALR：rd = PC+4，PC = (rs1 + imm(I)) & ~1
                //--------------------------------------------------------------
                OP_JALR: begin
                    if (funct3 == 3'b000) begin
                        ctrl_d.imm_sel   = IMM_I;
                        ctrl_d.jalr      = 1'b1;
                        ctrl_d.reg_write = 1'b1;
                        ctrl_d.rs1_used  = 1'b1;
                    end else begin
                        ctrl_d.illegal = 1'b1;
                    end
                end

                //--------------------------------------------------------------
                // 条件分支：比较 rs1/rs2，目标 PC = PC + imm(B)
                //--------------------------------------------------------------
                OP_BRANCH: begin
                    ctrl_d.imm_sel   = IMM_B;
                    ctrl_d.branch    = 1'b1;
                    ctrl_d.funct3    = funct3;
                    ctrl_d.rs1_used  = 1'b1;
                    ctrl_d.rs2_used  = 1'b1;
                end

                //--------------------------------------------------------------
                // LOAD：rd = mem[rs1 + imm(I)]
                //--------------------------------------------------------------
                OP_LOAD: begin
                    ctrl_d.imm_sel      = IMM_I;
                    ctrl_d.alu_op       = ALU_ADD;
                    ctrl_d.alu_src      = 1'b1;
                    ctrl_d.mem_read     = 1'b1;
                    ctrl_d.mem_size     = funct3[1:0];
                    ctrl_d.mem_unsigned = funct3[2];
                    ctrl_d.reg_write    = 1'b1;
                    ctrl_d.rs1_used     = 1'b1;
                end

                //--------------------------------------------------------------
                // STORE：mem[rs1 + imm(S)] = rs2
                //--------------------------------------------------------------
                OP_STORE: begin
                    ctrl_d.imm_sel   = IMM_S;
                    ctrl_d.alu_op    = ALU_ADD;
                    ctrl_d.alu_src   = 1'b1;
                    ctrl_d.mem_write = 1'b1;
                    ctrl_d.mem_size  = funct3[1:0];
                    ctrl_d.rs1_used  = 1'b1;
                    ctrl_d.rs2_used  = 1'b1;
                end

                //--------------------------------------------------------------
                // OP-IMM：寄存器-立即数运算
                //--------------------------------------------------------------
                OP_OPIMM: begin
                    ctrl_d.imm_sel   = IMM_I;
                    ctrl_d.alu_src   = 1'b1;
                    ctrl_d.reg_write = 1'b1;
                    ctrl_d.rs1_used  = 1'b1;
                    ctrl_d.funct3    = funct3;

                    unique case (funct3)
                        3'b000: ctrl_d.alu_op = ALU_ADD;                       // addi
                        3'b010: ctrl_d.alu_op = ALU_SLT;                       // slti
                        3'b011: ctrl_d.alu_op = ALU_SLTU;                      // sltiu
                        3'b100: ctrl_d.alu_op = ALU_XOR;                       // xori
                        3'b110: ctrl_d.alu_op = ALU_OR;                        // ori
                        3'b111: ctrl_d.alu_op = ALU_AND;                       // andi
                        3'b001: begin                                          // slli
                            if (funct7 == 7'b0000000)
                                ctrl_d.alu_op = ALU_SLL;
                            else
                                ctrl_d.illegal = 1'b1;
                        end
                        3'b101: begin                                          // srli / srai
                            if (funct7 == 7'b0000000)
                                ctrl_d.alu_op = ALU_SRL;
                            else if (funct7 == 7'b0100000)
                                ctrl_d.alu_op = ALU_SRA;
                            else
                                ctrl_d.illegal = 1'b1;
                        end
                    endcase
                end

                //--------------------------------------------------------------
                // OP：寄存器-寄存器运算（RV32I 基础 + RV32M 扩展）
                //--------------------------------------------------------------
                OP_OP: begin
                    ctrl_d.reg_write = 1'b1;
                    ctrl_d.rs1_used  = 1'b1;
                    ctrl_d.rs2_used  = 1'b1;
                    ctrl_d.funct3    = funct3;

                    if (funct7 == F7_M_EXT) begin
                        // RV32M：funct3 0~3 为乘法，4~7 为除法
                        ctrl_d.mul_en = (funct3[2] == 1'b0);
                        ctrl_d.div_en = (funct3[2] == 1'b1);
                    end else begin
                        unique case (funct3)
                            3'b000: ctrl_d.alu_op = (funct7 == 7'b0100000) ? ALU_SUB : ALU_ADD;
                            3'b001: ctrl_d.alu_op = ALU_SLL;
                            3'b010: ctrl_d.alu_op = ALU_SLT;
                            3'b011: ctrl_d.alu_op = ALU_SLTU;
                            3'b100: ctrl_d.alu_op = ALU_XOR;
                            3'b101: ctrl_d.alu_op = (funct7 == 7'b0100000) ? ALU_SRA : ALU_SRL;
                            3'b110: ctrl_d.alu_op = ALU_OR;
                            3'b111: ctrl_d.alu_op = ALU_AND;
                            default: ctrl_d.illegal = 1'b1;
                        endcase
                        // 基础整数 R 型仅允许 funct7=0x00 / 0x20
                        if ((funct7 != 7'b0000000) && (funct7 != 7'b0100000))
                            ctrl_d.illegal = 1'b1;
                    end
                end

                //--------------------------------------------------------------
                // SYSTEM：CSR 指令 / ecall / ebreak / mret
                //--------------------------------------------------------------
                OP_SYSTEM: begin
                    if (funct3 == 3'b000) begin
                        // 无 funct3 的系统指令
                        unique case (ifid_inst_i[31:20])
                            12'h000: ctrl_d.ecall  = 1'b1;   // ecall
                            12'h001: ctrl_d.ebreak = 1'b1;   // ebreak
                            12'h302: ctrl_d.mret   = 1'b1;   // mret
                            default: ctrl_d.illegal = 1'b1;
                        endcase
                    end else if ((funct3 >= 3'b001) && (funct3 <= 3'b011)) begin
                        // csrrw / csrrs / csrrc（寄存器源）
                        ctrl_d.csr_op    = funct3[1:0];
                        ctrl_d.csr_addr  = ifid_inst_i[31:20];
                        ctrl_d.reg_write = 1'b1;
                        ctrl_d.rs1_used  = 1'b1;
                    end else if ((funct3 >= 3'b101) && (funct3 <= 3'b111)) begin
                        // csrrwi / csrrsi / csrrci（零扩展立即数源 zimm=rs1 字段）
                        ctrl_d.csr_op    = funct3[1:0];
                        ctrl_d.csr_imm   = 1'b1;
                        ctrl_d.csr_addr  = ifid_inst_i[31:20];
                        ctrl_d.reg_write = 1'b1;
                    end else begin
                        ctrl_d.illegal = 1'b1;
                    end
                end

                //--------------------------------------------------------------
                // fence 类：本核按 NOP 处理（默认空控制即可）
                //--------------------------------------------------------------
                OP_MISCMEM: begin
                    ctrl_d = '0;
                end

                default: begin
                    ctrl_d.illegal = 1'b1;
                end
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // 立即数生成器：按 imm_sel 拼出 32 位立即数（均做符号扩展）
    //--------------------------------------------------------------------------
    logic [31:0] imm_d;

    always_comb begin
        unique case (ctrl_d.imm_sel)
            IMM_I: imm_d = {{20{ifid_inst_i[31]}}, ifid_inst_i[31:20]};
            IMM_S: imm_d = {{20{ifid_inst_i[31]}}, ifid_inst_i[31:25], ifid_inst_i[11:7]};
            IMM_B: imm_d = {{20{ifid_inst_i[31]}}, ifid_inst_i[7],
                            ifid_inst_i[30:25], ifid_inst_i[11:8], 1'b0};
            IMM_U: imm_d = {ifid_inst_i[31:12], 12'b0};
            IMM_J: imm_d = {{12{ifid_inst_i[31]}}, ifid_inst_i[19:12],
                            ifid_inst_i[20], ifid_inst_i[30:21], 1'b0};
            default: imm_d = 32'b0;
        endcase
    end

    //--------------------------------------------------------------------------
    // EX -> ID 转发：EX 指令写回的寄存器恰为本级源寄存器时直接取其结果
    //--------------------------------------------------------------------------
    logic fwd_a, fwd_b;

    assign fwd_a = ex_wreg_i && (ex_rd_i != 5'd0) && (ex_rd_i == rs1);
    assign fwd_b = ex_wreg_i && (ex_rd_i != 5'd0) && (ex_rd_i == rs2);

    logic [31:0] operand_a, operand_b;
    assign operand_a = fwd_a ? ex_wdata_i : gpr_a_i;
    assign operand_b = fwd_b ? ex_wdata_i : gpr_b_i;

    //--------------------------------------------------------------------------
    // 冒险检测
    //   (1) load-use：EX 为 load 且本级使用其目的寄存器 -> 停顿一拍
    //   (2) CSR 写后读：EX 在写某 CSR、本级又访问同一 CSR -> 停顿一拍
    //--------------------------------------------------------------------------
    logic load_hazard, csr_hazard;

    assign load_hazard = ex_mem_read_i && (ex_rd_i != 5'd0) &&
                         ((ctrl_d.rs1_used && (ex_rd_i == rs1)) ||
                          (ctrl_d.rs2_used && (ex_rd_i == rs2)));

    assign csr_hazard  = ex_csr_we_i && (ctrl_d.csr_op != CSR_NONE) &&
                         (ex_csr_addr_i == ctrl_d.csr_addr);

    assign stall_o = ifid_valid_i && (load_hazard || csr_hazard);

    //--------------------------------------------------------------------------
    // ID/EX 流水线寄存器
    //   stall/flush 时注入气泡（valid=0），其余周期正常锁存。
    //--------------------------------------------------------------------------
    logic [31:0] idex_pc_r;
    logic        idex_valid_r;
    ctrl_bus_t   idex_ctrl_r;
    logic [4:0]  idex_rs1_r, idex_rs2_r, idex_rd_r;
    logic [31:0] idex_reg_a_r, idex_reg_b_r, idex_imm_r, idex_inst_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idex_pc_r    <= '0;
            idex_valid_r <= 1'b0;
            idex_ctrl_r  <= '0;
            idex_rs1_r   <= '0;
            idex_rs2_r   <= '0;
            idex_rd_r    <= '0;
            idex_reg_a_r <= '0;
            idex_reg_b_r <= '0;
            idex_imm_r   <= '0;
            idex_inst_r  <= INST_NOP;
        end else if (stall_o || flush_i) begin
            // 停顿或冲刷：ID/EX 注入气泡
            idex_pc_r    <= '0;
            idex_valid_r <= 1'b0;
            idex_ctrl_r  <= '0;
            idex_rs1_r   <= '0;
            idex_rs2_r   <= '0;
            idex_rd_r    <= '0;
            idex_reg_a_r <= '0;
            idex_reg_b_r <= '0;
            idex_imm_r   <= '0;
            idex_inst_r  <= INST_NOP;
        end else begin
            idex_pc_r    <= ifid_pc_i;
            idex_valid_r <= ifid_valid_i;
            idex_ctrl_r  <= ctrl_d;
            idex_rs1_r   <= rs1;
            idex_rs2_r   <= rs2;
            idex_rd_r    <= rd;
            idex_reg_a_r <= operand_a;
            idex_reg_b_r <= operand_b;
            idex_imm_r   <= imm_d;
            idex_inst_r  <= ifid_inst_i;
        end
    end

    assign idex_pc_o    = idex_pc_r;
    assign idex_valid_o = idex_valid_r;
    assign idex_ctrl_o  = idex_ctrl_r;
    assign idex_rs1_o   = idex_rs1_r;
    assign idex_rs2_o   = idex_rs2_r;
    assign idex_rd_o    = idex_rd_r;
    assign idex_reg_a_o = idex_reg_a_r;
    assign idex_reg_b_o = idex_reg_b_r;
    assign idex_imm_o   = idex_imm_r;
    assign idex_inst_o  = idex_inst_r;

endmodule
