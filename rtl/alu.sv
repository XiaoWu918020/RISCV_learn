//==============================================================================
// File        : alu.sv
// Module      : alu —— 算术逻辑单元（纯组合）
// Description : 实现 RV32I 基础整数运算：加减、移位、有/无符号比较、
//               与或异或等。移位量取 b[4:0]（RISC-V 仅使用低 5 位）。
//==============================================================================
module alu (
    input  logic [31:0] a,          // 操作数 A
    input  logic [31:0] b,          // 操作数 B
    input  logic [4:0]  alu_op,     // 操作编码（riscv_defines）
    output logic [31:0] y           // 运算结果
);

    import riscv_defines::*;

    always_comb begin
        unique case (alu_op)
            ALU_ADD:  y = a + b;
            ALU_SUB:  y = a - b;
            ALU_SLL:  y = a << b[4:0];
            ALU_SLT:  y = {31'b0, $signed(a) < $signed(b)};
            ALU_SLTU: y = {31'b0, a < b};
            ALU_XOR:  y = a ^ b;
            ALU_SRL:  y = a >> b[4:0];
            ALU_SRA:  y = $signed(a) >>> b[4:0];
            ALU_OR:   y = a | b;
            ALU_AND:  y = a & b;
            default:  y = 32'b0;
        endcase
    end

endmodule
