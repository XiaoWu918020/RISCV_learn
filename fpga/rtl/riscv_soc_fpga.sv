//==============================================================================
// File        : riscv_soc_fpga.sv
// Module      : riscv_soc_fpga —— 面向 FPGA 上板的 SoC 顶层
// Description : 复用已验证的三级流水线核 riscv_core，把核数据口的访问按地址
//               译码路由到四类从设备，并用读 mux 返回对应数据：
//                 IMEM  0x0000_0000  指令/只读常量（数据口只读，双读口 RAM）
//                 UART  0x1000_0000  串口打印（新增外设）
//                 DMEM  0x2000_0000  数据/堆栈（字节写）
//                 CLINT 0x4000_0000  中断/定时器（核内 CLINT）
//               存储采用可综合的 fpga_ram（异步读，推断分布式 RAM），与核
//               “当拍取数”时序对齐，故核内 RTL 无需任何改动。
//==============================================================================
`include "riscv_types.svh"
module riscv_soc_fpga #(
    parameter logic [31:0] PC_RST      = 32'h0000_0000,
    parameter logic [31:0] IMEM_BASE   = 32'h0000_0000,
    parameter int          IMEM_WORDS  = 4096,           // 16 KB
    parameter logic [31:0] UART_BASE   = 32'h1000_0000,
    parameter logic [31:0] UART_SIZE   = 32'h0000_0100,
    parameter logic [31:0] GPO_BASE    = 32'h1000_1000,  // LED 输出寄存器
    parameter logic [31:0] GPO_SIZE    = 32'h0000_0100,
    parameter logic [31:0] DMEM_BASE   = 32'h2000_0000,
    parameter int          DMEM_WORDS  = 16384,          // 64 KB
    parameter logic [31:0] CLINT_BASE  = 32'h4000_0000,
    parameter logic [31:0] CLINT_SIZE  = 32'h0000_C000,
    parameter int          CLK_FREQ    = 25_000_000,          // 系统时钟频率（UART 波特率分频用）
    parameter              HEX_FILE    = "hex/firmware.hex"
) (
    input  logic clk,
    input  logic rst_n,
    input  logic ext_irq,

    // 板级观测/串口
    output logic uart_tx,
    output logic [31:0] gpo_o          // LED 输出寄存器（板级接 LED）
);

    import riscv_defines::*;

    //--------------------------------------------------------------------------
    // 核对外接口信号
    //--------------------------------------------------------------------------
    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_wbe;
    logic        dmem_en;
    logic [31:0] clint_addr, clint_wdata, clint_rdata;
    logic        clint_we, clint_re;

    //--------------------------------------------------------------------------
    // 地址译码选择
    //--------------------------------------------------------------------------
    logic imem_sel, dmem_sel, clint_sel, uart_sel, gpo_sel;

    assign imem_sel  = (dmem_addr >= IMEM_BASE) &&
                       (dmem_addr <  IMEM_BASE + (IMEM_WORDS * 4));
    assign uart_sel  = (dmem_addr >= UART_BASE) &&
                       (dmem_addr <  UART_BASE + UART_SIZE);
    assign gpo_sel   = (dmem_addr >= GPO_BASE) &&
                       (dmem_addr <  GPO_BASE + GPO_SIZE);
    assign dmem_sel  = (dmem_addr >= DMEM_BASE) &&
                       (dmem_addr <  DMEM_BASE + (DMEM_WORDS * 4));
    assign clint_sel = (dmem_addr >= CLINT_BASE) &&
                       (dmem_addr <  CLINT_BASE + CLINT_SIZE);

    //==========================================================================
    // 核心例化
    //==========================================================================
    riscv_core #(
        .PC_RST (PC_RST)
    ) u_core (
        .clk          (clk),
        .rst_n        (rst_n),
        .imem_addr    (imem_addr),
        .imem_rdata   (imem_rdata),
        .dmem_addr    (dmem_addr),
        .dmem_wdata   (dmem_wdata),
        .dmem_wbe     (dmem_wbe),
        .dmem_en      (dmem_en),
        .dmem_rdata   (dmem_rdata),
        .clint_addr   (clint_addr),
        .clint_wdata  (clint_wdata),
        .clint_we     (clint_we),
        .clint_re     (clint_re),
        .clint_rdata  (clint_rdata),
        .ext_irq     (ext_irq)
    );

    //==========================================================================
    // 指令存储器 IMEM（异步读，双读口；$readmemh 加载固件）
    //   读口1：指令口，按 imem_addr 取指
    //   读口2：数据口只读窗口，按 dmem_addr 取常量
    //==========================================================================
    logic [31:0] imem_dread;

    // 取指与数据口各使用一份单读口 ROM，规避双异步读初始化 RAM 的综合映射异常
    fpga_rom #(
        .WIDTH(32), .DEPTH(IMEM_WORDS), .INIT_FILE(HEX_FILE)
    ) u_imem_fetch (
        .raddr_i (imem_addr[$clog2(IMEM_WORDS)+1:2]),
        .rdata_o (imem_rdata)
    );

    fpga_rom #(
        .WIDTH(32), .DEPTH(IMEM_WORDS), .INIT_FILE(HEX_FILE)
    ) u_imem_data (
        .raddr_i (dmem_addr[$clog2(IMEM_WORDS)+1:2]),
        .rdata_o (imem_dread)
    );

    //==========================================================================
    // 数据存储器 DMEM（异步读 + 同步字节写）
    //==========================================================================
    logic [31:0] dmem_read;
    logic [31:0] dmem_offset;
    assign dmem_offset = dmem_addr - DMEM_BASE;

    fpga_ram #(
        .WIDTH (32),
        .DEPTH (DMEM_WORDS)
    ) u_dmem (
        .clk      (clk),
        .waddr_i  (dmem_offset[$clog2(DMEM_WORDS)+1:2]),
        .wdata_i  (dmem_wdata),
        .wbe_i    (dmem_wbe),
        .we_i     (dmem_en && dmem_sel),
        .raddr_i  (dmem_offset[$clog2(DMEM_WORDS)+1:2]),
        .rdata_o  (dmem_read),
        .r2addr_i ('0),
        .r2data_o ()
    );

    //==========================================================================
    // CLINT 访问转接（核内 CLINT）
    //==========================================================================
    assign clint_addr  = dmem_addr;
    assign clint_wdata = dmem_wdata;
    assign clint_we    = dmem_en && clint_sel && (|dmem_wbe);
    assign clint_re    = dmem_en && clint_sel && ~(|dmem_wbe);

    //==========================================================================
    // UART 外设（内存映射，轮询发送）
    //==========================================================================
    logic [31:0] uart_rdata;
    logic        uart_reg_we;
    assign uart_reg_we = dmem_en && uart_sel && (|dmem_wbe);

    uart #(
        .CLK_FREQ (CLK_FREQ)          // 按实际系统时钟计算波特率分频
    ) u_uart (
        .clk         (clk),
        .rst_n       (rst_n),
        .reg_addr_i  (dmem_addr[3:0]),
        .reg_wdata_i (dmem_wdata),
        .reg_we_i    (uart_reg_we),
        .reg_rdata_o (uart_rdata),
        .tx_o        (uart_tx)
    );

    //==========================================================================
    // GPO 输出寄存器（驱动板级 LED）：选中且写时更新，复位清零
    //==========================================================================
    logic gpo_we;
    assign gpo_we = dmem_en && gpo_sel && (|dmem_wbe);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            gpo_o <= 32'b0;
        else if (gpo_we)
            gpo_o <= dmem_wdata;
    end

    //==========================================================================
    // 读数据 mux：默认 0，按译码选择从设备（纯组合，无锁存）
    //==========================================================================
    always_comb begin
        dmem_rdata = 32'b0;
        if (clint_sel)
            dmem_rdata = clint_rdata;
        else if (dmem_sel)
            dmem_rdata = dmem_read;
        else if (uart_sel)
            dmem_rdata = uart_rdata;
        else if (gpo_sel)
            dmem_rdata = gpo_o;
        else if (imem_sel)
            dmem_rdata = imem_dread;
    end

endmodule
