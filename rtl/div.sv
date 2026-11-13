//==============================================================================
// File        : div.sv
// Module      : div —— RV32M 除法单元（纯组合）
// Description : 按 funct3 实现四条除法/取余指令：
//                 funct3=4 div  ：有符号商
//                 funct3=5 divu ：无符号商
//                 funct3=6 rem  ：有符号余数
//                 funct3=7 remu ：无符号余数
//               按 RISC-V 规范处理两类特殊情况：
//                 (1) 除数为 0：商 = 0xFFFFFFFF，余数 = 被除数
//                 (2) 有符号溢出 0x80000000 / -1：商 = 0x80000000，余数 = 0
// Note        : 组合除法面积/延迟较大，如需更高频率可替换为多周期迭代除法器，
//               并在流水线中插入对应拍数的停顿（接口保持不变）。
//==============================================================================
module div (
    input  logic [31:0] a,          // 被除数
    input  logic [31:0] b,          // 除数
    input  logic [2:0]  funct3,     // M 扩展子操作编码
    output logic [31:0] y           // 商或余数
);

    logic signed [31:0] sa, sb;
    assign sa = a;
    assign sb = b;

    always_comb begin
        unique case (funct3)
            // 有符号商
            3'b100: begin
                if (b == 32'b0)
                    y = 32'hFFFF_FFFF;                       // 除零
                else if ((a == 32'h8000_0000) && (b == 32'hFFFF_FFFF))
                    y = 32'h8000_0000;                       // 有符号溢出
                else
                    y = sa / sb;
            end
            // 无符号商
            3'b101: begin
                if (b == 32'b0) y = 32'hFFFF_FFFF;           // 除零
                else            y = a / b;
            end
            // 有符号余数
            3'b110: begin
                if (b == 32'b0)
                    y = a;                                    // 除零：余数=被除数
                else if ((a == 32'h8000_0000) && (b == 32'hFFFF_FFFF))
                    y = 32'b0;                                // 有符号溢出
                else
                    y = sa % sb;
            end
            // 无符号余数
            3'b111: begin
                if (b == 32'b0) y = a;                        // 除零
                else            y = a % b;
            end
            default: y = 32'b0;
        endcase
    end

endmodule
