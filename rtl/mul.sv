//==============================================================================
// File        : mul.sv
// Module      : mul —— RV32M 乘法单元（纯组合）
// Description : 按 funct3 实现四条乘法指令：
//                 funct3=0  mul    ：乘积低 32 位（有/无符号结果相同）
//                 funct3=1  mulh   ：有符号 × 有符号，乘积高 32 位
//                 funct3=2  mulhsu ：有符号 × 无符号，乘积高 32 位
//                 funct3=3  mulhu  ：无符号 × 无符号，乘积高 32 位
//               实现技巧：把操作数统一扩展为 33 位有符号数（无符号数补 0
//               后数值不变），全程使用有符号乘法得到 66 位乘积，避免混合
//               符号类型导致的隐式转换错误。综合时工具自动映射 DSP。
//==============================================================================
module mul (
    input  logic [31:0] a,          // 操作数 A
    input  logic [31:0] b,          // 操作数 B
    input  logic [2:0]  funct3,     // M 扩展子操作编码
    output logic [31:0] y           // 输出结果
);

    // 33 位有符号扩展：有符号数符号扩展，无符号数高位补 0
    logic signed [32:0] a_s, b_s;   // 有符号视角
    logic signed [32:0] a_u, b_u;   // 无符号视角（作为正数的有符号数）

    assign a_s = {a[31], a};
    assign b_s = {b[31], b};
    assign a_u = {1'b0, a};
    assign b_u = {1'b0, b};

    // 66 位有符号乘积
    logic signed [65:0] p_ss, p_su, p_uu;
    assign p_ss = a_s * b_s;        // 有符号 × 有符号
    assign p_su = a_s * b_u;        // 有符号 × 无符号
    assign p_uu = a_u * b_u;        // 无符号 × 无符号

    always_comb begin
        unique case (funct3)
            3'b000:  y = (a * b);       // mul：低 32 位
            3'b001:  y = p_ss[63:32];   // mulh
            3'b010:  y = p_su[63:32];   // mulhsu
            3'b011:  y = p_uu[63:32];   // mulhu
            default: y = 32'b0;
        endcase
    end

endmodule
