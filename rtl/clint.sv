//==============================================================================
// File        : clint.sv
// Module      : clint —— 核心本地中断器（CLINT, Core Local INTruptor）
// Description : 生成 RISC-V M 模式三类中断挂起位 mip，并提供存储器映射寄存器：
//               机器软件中断 MSIP、64 位机器定时器 mtime/mtimecmp。
//
//   寄存器采用标准 SiFive CLINT 偏移（相对 CLINT 基址，基址需 64KB 对齐）：
//     0x0000 : MSIP      机器软件中断挂起（仅 bit0 有效）
//     0x4000 : MTIMECMPL mtimecmp 低 32 位
//     0x4004 : MTIMECMPH mtimecmp 高 32 位
//     0xBFF8 : MTIMEL    mtime 低 32 位
//     0xBFFC : MTIMEH    mtime 高 32 位
//   注：本模块对全地址的低 16 位 addr_i[15:0] 译码。
//
//   mtimecmp 复位值为全 1（64'hFFFF_FFFF_FFFF_FFFF），保证复位后
//   mtime(从0递增) < mtimecmp，定时器中断不会在软件配置前误触发。
//
// 中断映射（对应 RISC-V mip 位）：
//   bit3  MSIP   -> 机器软件中断
//   bit7  MTIP   -> 机器定时器中断（mtime >= mtimecmp）
//   bit11 MEIP   -> 机器外部中断（同步 ext_irq_i 电平）
//==============================================================================
module clint (
    input  logic        clk,
    input  logic        rst_n,        // 异步低有效复位

    // 存储器映射寄存器接口
    input  logic [31:0] addr_i,       // 全地址（内部取 [15:0]）
    input  logic [31:0] wdata_i,
    input  logic        we_i,         // 写使能
    input  logic        re_i,         // 读使能
    output logic [31:0] rdata_o,

    // 中断挂起位图输出（bit3=MS, bit7=MT, bit11=ME）
    output logic [31:0] mip_o,

    input  logic        ext_irq_i     // 外部中断原始电平
);

    //--------------------------------------------------------------------------
    // 标准 CLINT 寄存器偏移（低 16 位）
    //--------------------------------------------------------------------------
    localparam logic [15:0] A_MSIP  = 16'h0000;
    localparam logic [15:0] A_MTCL  = 16'h4000;
    localparam logic [15:0] A_MTCH  = 16'h4004;
    localparam logic [15:0] A_MTL   = 16'hBFF8;
    localparam logic [15:0] A_MTH   = 16'hBFFC;

    //--------------------------------------------------------------------------
    // 内部寄存器
    //--------------------------------------------------------------------------
    logic        msip_r;              // 软件中断挂起
    logic [63:0] mtimecmp_r;          // 定时器比较值（复位全 1）
    logic [63:0] mtime_r;             // 实时计数器（复位 0）
    logic [31:0] mip_r;               // 中断挂起位图

    // 写 mtime 半字的译码（写优先于自增）
    logic mtime_wr_l, mtime_wr_h;
    assign mtime_wr_l = we_i && (addr_i[15:0] == A_MTL);
    assign mtime_wr_h = we_i && (addr_i[15:0] == A_MTH);

    //--------------------------------------------------------------------------
    // 寄存器写 / mtime 递增
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            msip_r     <= 1'b0;
            mtimecmp_r <= 64'hFFFF_FFFF_FFFF_FFFF;
            mtime_r    <= 64'd0;
        end else begin
            //------ MSIP / mtimecmp 写 ------
            if (we_i) begin
                unique case (addr_i[15:0])
                    A_MSIP: msip_r              <= wdata_i[0];
                    A_MTCH: mtimecmp_r[63:32]   <= wdata_i;
                    A_MTCL: mtimecmp_r[31:0]    <= wdata_i;
                    default: ;
                endcase
            end

            //------ mtime：默认每拍 +1，软件写某半字时该半字写入优先 ------
            if (mtime_wr_l)
                mtime_r[31:0] <= wdata_i;
            else if (mtime_wr_h)
                mtime_r[63:32] <= wdata_i;
            else
                mtime_r <= mtime_r + 64'd1;
        end
    end

    //--------------------------------------------------------------------------
    // 寄存器读（仅在读使能时输出，否则返回 0）
    //--------------------------------------------------------------------------
    always_comb begin
        if (!re_i) begin
            rdata_o = 32'b0;
        end else begin
            unique case (addr_i[15:0])
                A_MSIP: rdata_o = {31'b0, msip_r};
                A_MTCL: rdata_o = mtimecmp_r[31:0];
                A_MTCH: rdata_o = mtimecmp_r[63:32];
                A_MTL:  rdata_o = mtime_r[31:0];
                A_MTH:  rdata_o = mtime_r[63:32];
                default: rdata_o = 32'b0;
            endcase
        end
    end

    //--------------------------------------------------------------------------
    // 中断挂起位图 mip
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mip_r <= 32'b0;
        else begin
            mip_r[3]  <= msip_r;
            mip_r[7]  <= (mtime_r >= mtimecmp_r);
            mip_r[11] <= ext_irq_i;
        end
    end

    //--------------------------------------------------------------------------
    // 中断挂起位图输出
    //--------------------------------------------------------------------------
    assign mip_o = mip_r;

endmodule
