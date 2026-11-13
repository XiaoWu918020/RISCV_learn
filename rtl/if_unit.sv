//==============================================================================
// File        : if_unit.sv
// Module      : if_unit  —— 一级流水线：取指单元（IF）
// Description : 对应框图 IF_UNIT，内部包含：
//                 (1) pc        ：程序计数器及其更新逻辑
//                 (2) if_id     ：IF -> ID 流水线寄存器
//               取指地址 pc 直接输出到指令存储器（组合读模型），取到的指令
//               在时钟沿锁入 if_id 后送往二级译码。
//               支持：顺序取指(pc+4)、跳转/中断重定向、流水线停顿、冲刷。
//==============================================================================
module if_unit #(
    parameter logic [31:0] PC_RST = 32'h0000_0000  // 复位入口地址
) (
    input  logic        clk,            // 时钟
    input  logic        rst_n,          // 异步低电平复位

    // 流水线控制
    input  logic        stall_i,        // 停顿：PC 与 if_id 保持不变
    input  logic        flush_i,        // 冲刷：if_id 注入气泡（跳转/异常）
    input  logic        pc_sel_i,       // PC 选择：1=跳转到 pc_new_i，0=pc+4
    input  logic [31:0] pc_new_i,       // 跳转/异常目标地址

    // 指令存储器接口（组合读：地址有效当周期返回指令）
    output logic [31:0] imem_addr_o,    // 取指地址 = 当前 PC
    input  logic [31:0] imem_rdata_i,   // 指令存储器读出数据

    // IF/ID 寄存器输出（送往 id_unit）
    output logic [31:0] ifid_pc_o,      // 取指级指令对应的 PC
    output logic [31:0] ifid_inst_o,    // 取指级指令
    output logic        ifid_valid_o    // 有效位：0 表示气泡
);

    import riscv_defines::*;

    //--------------------------------------------------------------------------
    // 程序计数器 pc
    //--------------------------------------------------------------------------
    logic [31:0] pc_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pc_r <= PC_RST;
        end else if (!stall_i) begin
            // 停顿时保持；否则按重定向/顺序更新
            pc_r <= pc_sel_i ? pc_new_i : (pc_r + 32'd4);
        end
    end

    assign imem_addr_o = pc_r;

    //--------------------------------------------------------------------------
    // IF/ID 流水线寄存器
    //--------------------------------------------------------------------------
    logic [31:0] ifid_pc_r;
    logic [31:0] ifid_inst_r;
    logic        ifid_valid_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ifid_pc_r    <= '0;
            ifid_inst_r  <= INST_NOP;
            ifid_valid_r <= 1'b0;
        end else if (stall_i) begin
            // 停顿：整组保持
            ifid_pc_r    <= ifid_pc_r;
            ifid_inst_r  <= ifid_inst_r;
            ifid_valid_r <= ifid_valid_r;
        end else if (flush_i) begin
            // 冲刷：注入气泡
            ifid_pc_r    <= '0;
            ifid_inst_r  <= INST_NOP;
            ifid_valid_r <= 1'b0;
        end else begin
            // 正常锁存当前取指结果
            ifid_pc_r    <= pc_r;
            ifid_inst_r  <= imem_rdata_i;
            ifid_valid_r <= 1'b1;
        end
    end

    assign ifid_pc_o    = ifid_pc_r;
    assign ifid_inst_o  = ifid_inst_r;
    assign ifid_valid_o = ifid_valid_r;

endmodule
