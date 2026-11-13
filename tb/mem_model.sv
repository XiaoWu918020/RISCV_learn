//==============================================================================
// File        : mem_model.sv
// Description : testbench 用存储器行为模型
//   imem_model : 指令存储器，组合读（地址当周期出指令），$readmemh 加载
//   dmem_model : 数据存储器，组合读 + 时钟沿字节写，支持 wbe 字节掩码
// 注：字索引按字节地址的高 30 位（addr[31:2]）寻址，低 2 位用于字节选择。
//==============================================================================

//------------------------------------------------------------------------------
// 指令存储器
//------------------------------------------------------------------------------
module imem_model #(
    parameter logic [31:0] DEPTH = 4096
) (
    input  logic [31:0] addr,
    output logic [31:0] rdata
);

    logic [31:0] mem [DEPTH];

    // 组合读：未初始化位置返回 0
    assign rdata = mem[addr[31:2]];

endmodule

//------------------------------------------------------------------------------
// 数据存储器
//------------------------------------------------------------------------------
module dmem_model #(
    parameter logic [31:0] DEPTH = 4096
) (
    input  logic        clk,
    input  logic [31:0] addr,
    input  logic [31:0] wdata,
    input  logic [3:0]  wbe,       // 字节写使能
    input  logic        en,        // 访问使能
    output logic [31:0] rdata
);

    logic [31:0] mem [DEPTH];

    // 组合读
    assign rdata = mem[addr[31:2]];

    // 同步字节写
    always_ff @(posedge clk) begin
        if (en) begin
            if (wbe[0]) mem[addr[31:2]][7:0]  <= wdata[7:0];
            if (wbe[1]) mem[addr[31:2]][15:8] <= wdata[15:8];
            if (wbe[2]) mem[addr[31:2]][23:16] <= wdata[23:16];
            if (wbe[3]) mem[addr[31:2]][31:24] <= wdata[31:24];
        end
    end

endmodule
