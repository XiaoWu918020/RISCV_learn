//==============================================================================
// File        : fpga_rom.sv
// Module      : fpga_rom —— 单异步读口初始化 ROM
// Description : 用于 FPGA IMEM。取指口与数据口分别例化一份 ROM，避免 Vivado
//               对“同一存储数组双异步读 + 初始化”的分布式 RAM 推断出现读口
//               地址/数据映射异常。显式存储下标范围，保证 $readmemh 从 word 0
//               开始加载。面积增加一份 IMEM 镜像，换取确定、可验证的综合行为。
//==============================================================================
module fpga_rom #(
    parameter int          WIDTH     = 32,
    parameter int          DEPTH     = 4096,
    parameter              INIT_FILE = ""
) (
    input  logic [$clog2(DEPTH)-1:0] raddr_i,
    output logic [WIDTH-1:0]         rdata_o
);

    logic [WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end
    end

    assign rdata_o = mem[raddr_i];

endmodule
