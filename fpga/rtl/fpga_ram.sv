//==============================================================================
// File        : fpga_ram.sv
// Module      : fpga_ram —— FPGA 可综合单口写 / 异步读 RAM
// Description : 为上板封装的行为存储，读端口为“地址变化当拍出数据”的异步读，
//               与本核“取指/load 当拍取数”的时序严格对齐，因此 Vivado 会将
//               其推断为分布式 RAM（LUT RAM），无需改动已验证的核内流水线。
//               写端口为时钟沿同步写，支持按字节使能；INIT_FILE 非空时在
//               initial 中用 $readmemh 加载初始镜像（用于 IMEM 固件，可综合）。
// Note        : 本核目标器件 xczu15eg 资源充裕，分布式 RAM 面积占比很小；
//               若后续希望改用 Block RAM，需把读端口改为同步读并在核内
//               增加相应的取指/访存拍数适配。
//==============================================================================
module fpga_ram #(
    parameter int          WIDTH     = 32,             // 数据位宽
    parameter int          DEPTH     = 16384,          // 存储字数
    parameter              INIT_FILE = ""              // 初始化 hex，空串=不初始化
) (
    input  logic                        clk,            // 时钟
    // 写端口（同步）
    input  logic [$clog2(DEPTH)-1:0]    waddr_i,        // 写地址（字索引）
    input  logic [WIDTH-1:0]            wdata_i,        // 写数据
    input  logic [WIDTH/8-1:0]          wbe_i,          // 字节写使能
    input  logic                        we_i,           // 写使能
    // 读端口 1（异步/组合）
    input  logic [$clog2(DEPTH)-1:0]    raddr_i,        // 读地址（字索引）
    output logic [WIDTH-1:0]            rdata_o,        // 读数据
    // 读端口 2（异步/组合，IMEM 数据口只读窗口用；DMEM 可悬空）
    input  logic [$clog2(DEPTH)-1:0]    r2addr_i,
    output logic [WIDTH-1:0]            r2data_o
);

    // 实际存储数组
    logic [WIDTH-1:0] mem [DEPTH];

    // 可选初始化：仅当传入文件名时加载（IMEM 固件）
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    // 同步写：按字节使能逐字节更新
    always_ff @(posedge clk) begin
        if (we_i) begin
            for (int b = 0; b < WIDTH/8; b++) begin
                if (wbe_i[b]) begin
                    mem[waddr_i][b*8 +: 8] <= wdata_i[b*8 +: 8];
                end
            end
        end
    end

    // 异步读：地址有效当拍输出，推断为分布式 RAM
    assign rdata_o  = mem[raddr_i];
    assign r2data_o = mem[r2addr_i];

endmodule
