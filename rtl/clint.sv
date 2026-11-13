//==============================================================================
// File        : clint.sv
// Module      : clint —— 核心本地中断器（CLINT）
// Description : 对应框图“中断 clint”，提供机器级三类中断挂起源：
//                 - MSIP 机器软件中断（存储器映射 1 位）
//                 - MTIP 机器定时器中断（64 位 mtime / mtimecmp 比较）
//                 - MEIP 机器外部中断（直接采样外部输入）
//               对外暴露简单存储器映射读写口，输出 mip 位图给 rf_unit。
// 本地地址映射（地址低 5 位）：
//     0x00 : msip       (bit0)
//     0x08 : mtimecmp低32位
//     0x0C : mtimecmp高32位
//     0x10 : mtime低32位
//     0x14 : mtime高32位
//==============================================================================
module clint (
    input  logic        clk,
    input  logic        rst_n,

    // 简易存储器映射总线
    input  logic [31:0] addr_i,         // 字节地址（仅译码低 5 位）
    input  logic [31:0] wdata_i,
    input  logic        we_i,
    input  logic        re_i,
    output logic [31:0] rdata_o,

    input  logic        ext_irq_i,      // 机器外部中断原始电平
    output logic [31:0] mip_o           // 中断挂起位图（bit3/7/11）
);

    import riscv_defines::*;

    //--------------------------------------------------------------------------
    // 内部寄存器
    //--------------------------------------------------------------------------
    logic        msip;
    logic [63:0] mtimecmp;
    logic [63:0] mtime;

    logic mtip;
    assign mtip = (mtime >= mtimecmp);

    //--------------------------------------------------------------------------
    // 寄存器写
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msip     <= 1'b0;
            mtimecmp <= 64'b0;
            mtime    <= 64'b0;
        end else begin
            // 自由运行计数器
            mtime <= mtime + 64'd1;

            if (we_i) begin
                unique case (addr_i[4:0])
                    5'h00: msip            <= wdata_i[0];
                    5'h08: mtimecmp[31:0]  <= wdata_i;
                    5'h0C: mtimecmp[63:32] <= wdata_i;
                    5'h10: mtime[31:0]     <= wdata_i;
                    5'h14: mtime[63:32]    <= wdata_i;
                    default: ;
                endcase
            end
        end
    end

    //--------------------------------------------------------------------------
    // 总线读
    //--------------------------------------------------------------------------
    always_comb begin
        if (!re_i) begin
            rdata_o = 32'b0;
        end else begin
            unique case (addr_i[4:0])
                5'h00: rdata_o = {31'b0, msip};
                5'h08: rdata_o = mtimecmp[31:0];
                5'h0C: rdata_o = mtimecmp[63:32];
                5'h10: rdata_o = mtime[31:0];
                5'h14: rdata_o = mtime[63:32];
                default: rdata_o = 32'b0;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // mip 位图输出
    //--------------------------------------------------------------------------
    always_comb begin
        mip_o = 32'b0;
        mip_o[M_INT_MS] = msip;
        mip_o[M_INT_MT] = mtip;
        mip_o[M_INT_ME] = ext_irq_i;
    end

endmodule
