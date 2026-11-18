//==============================================================================
// File        : riscv_soc.sv
// Module      : riscv_soc —— 面向 FreeRTOS 的最小片上系统（SoC）顶层
// Description : 集成三级流水线核 riscv_core（其内部已含 CLINT）、指令/数据存储，
//               并对核的数据口做统一地址译码，把访问路由到 CLINT 或 DMEM，
//               最后用读 mux 把对应从设备的读数据返回给核。
//
//   主数据通路（核 dmem 口）地址映射（均可由参数覆盖）：
//   +-----------+----------------+------------+----------------------------+
//   | 区域      | 基址           | 大小       | 说明                       |
//   +-----------+----------------+------------+----------------------------+
//   | IMEM      | 0x0000_0000    | IMEM_WORDS | 指令存储，复位 PC=0        |
//   | DMEM      | 0x2000_0000    | DMEM_WORDS | 数据/堆栈 RAM（可字节写）  |
//   | CLINT     | 0x4000_0000    | 0xC000     | 中断/定时器（核内 CLINT）  |
//   +-----------+----------------+------------+----------------------------+
//
//   CLINT 内部为标准 SiFive 偏移（相对 CLINT 基址）：
//     0x0000       : MSIP      机器软件中断挂起（bit0）
//     0x4000/0x4004: MTIMECMP 低/高 32 位（复位全 1，避免误触发）
//     0xBFF8/0xBFFC: MTIME    低/高 32 位
//   => FreeRTOS：configCLINT_BASE_ADDRESS 设为 0x4000_0000，可直接使用标准
//      RISC-V 端口的 MSIP/MTIMECMP/MTIME 偏移，无需再做特殊映射。
//
// 存储器均为行为模型：组合读 + 时钟沿字节写；IMEM 用 $readmemh 加载固件，
// 固件文件名可由参数 HEX_FILE 指定（便于不同 testbench 复用）。
//==============================================================================
`include "riscv_types.svh"
module riscv_soc #(
    parameter logic [31:0] PC_RST      = 32'h0000_0000,  // 复位入口
    parameter logic [31:0] IMEM_BASE   = 32'h0000_0000,  // 指令存储基址
    parameter int          IMEM_WORDS  = 4096,           // 指令字数（16 KB）
    parameter logic [31:0] DMEM_BASE   = 32'h2000_0000,  // 数据存储基址
    parameter int          DMEM_WORDS  = 16384,          // 数据字数（64 KB）
    parameter logic [31:0] UART_BASE   = 32'h1000_0000,  // UART 基址（与 FPGA SoC 对齐）
    parameter logic [31:0] UART_SIZE   = 32'h0000_0100,
    parameter logic [31:0] GPO_BASE    = 32'h1000_1000,  // GPO/LED 基址
    parameter logic [31:0] GPO_SIZE    = 32'h0000_0100,
    parameter logic [31:0] CLINT_BASE  = 32'h4000_0000,  // CLINT 基址
    parameter logic [31:0] CLINT_SIZE  = 32'h0000_C000,  // CLINT 译码窗口（48 KB）
    parameter              HEX_FILE    = "firmware.hex"  // 固件 hex 文件名
) (
    input  logic clk,          // 系统时钟
    input  logic rst_n,        // 异步低有效复位
    input  logic ext_irq       // 机器外部中断原始电平
);

    import riscv_defines::*;

    //--------------------------------------------------------------------------
    // 核对外接口信号
    //--------------------------------------------------------------------------
    // 指令口
    logic [31:0] imem_addr, imem_rdata;
    // 数据口
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_wbe;
    logic        dmem_en;
    // CLINT 存储器映射口（核内 CLINT）
    logic [31:0] clint_addr, clint_wdata, clint_rdata;
    logic        clint_we, clint_re;

    //--------------------------------------------------------------------------
    // 地址译码：按 [基址, 基址+大小) 窗口选中对应从设备
    //--------------------------------------------------------------------------
    logic imem_sel, dmem_sel, clint_sel, uart_sel, gpo_sel;

    // IMEM 数据口窗口：仅用于只读访问代码/只读常量（如 xISRStackTop），
    // 写逻辑不响应此选择，故对数据口而言 IMEM 天然只读。
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
        .ext_irq      (ext_irq)
    );

    //==========================================================================
    // 指令存储器 IMEM（组合读，$readmemh 加载固件）
    //==========================================================================
    logic [31:0] imem_mem [IMEM_WORDS];
    logic [31:0] imem_offset;

    assign imem_offset = imem_addr - IMEM_BASE;
    assign imem_rdata  = imem_mem[imem_offset[31:2]];

    initial begin
        // 固件文件名由参数 HEX_FILE 指定（相对仿真运行目录）
        $readmemh(HEX_FILE, imem_mem);
    end

    //==========================================================================
    // 数据存储器 DMEM（组合读 + 时钟沿字节写）
    //==========================================================================
    logic [31:0] dmem_mem [DMEM_WORDS];
    logic [31:0] dmem_offset;

    assign dmem_offset = dmem_addr - DMEM_BASE;

    // 组合读：始终按当前地址输出，由读 mux 决定是否采用
    logic [31:0] dmem_read_raw;
    assign dmem_read_raw = dmem_mem[dmem_offset[31:2]];

    // 同步字节写：仅在选中 DMEM 且有效时使能
    always_ff @(posedge clk) begin
        if (dmem_en && dmem_sel) begin
            if (dmem_wbe[0]) dmem_mem[dmem_offset[31:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_wbe[1]) dmem_mem[dmem_offset[31:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_wbe[2]) dmem_mem[dmem_offset[31:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_wbe[3]) dmem_mem[dmem_offset[31:2]][31:24] <= dmem_wdata[31:24];
        end
    end

    //==========================================================================
    // CLINT 访问控制：把核数据口的访问转接到核内 CLINT 端口
    //   wbe 非 0 视为写，否则视为读（CLINT 仅支持 32 位对齐访问）
    //==========================================================================
    assign clint_addr  = dmem_addr;                 // CLINT 内部仅取 addr[4:0]
    assign clint_wdata = dmem_wdata;
    assign clint_we    = dmem_en && clint_sel && (|dmem_wbe);
    assign clint_re    = dmem_en && clint_sel && ~(|dmem_wbe);

    //==========================================================================
    // UART 外设（与 FPGA SoC 同一模块，仿真即可验证完整固件；tx 内部观测）
    //==========================================================================
    logic [31:0] uart_rdata;
    logic        uart_tx;
    logic        uart_reg_we;
    assign uart_reg_we = dmem_en && uart_sel && (|dmem_wbe);

    uart u_uart (
        .clk         (clk),
        .rst_n       (rst_n),
        .reg_addr_i  (dmem_addr[3:0]),
        .reg_wdata_i (dmem_wdata),
        .reg_we_i    (uart_reg_we),
        .reg_rdata_o (uart_rdata),
        .tx_o        (uart_tx)
    );

    //==========================================================================
    // GPO 输出寄存器（仿真中不接 LED，仅保证固件访问行为与 FPGA 一致）
    //==========================================================================
    logic [31:0] gpo;
    logic        gpo_we;
    assign gpo_we = dmem_en && gpo_sel && (|dmem_wbe);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            gpo <= 32'b0;
        else if (gpo_we)
            gpo <= dmem_wdata;
    end

    //==========================================================================
    // 读数据 mux：默认返回 0（未映射地址），按译码结果选择从设备
    //   先给默认值再分支，保证纯组合、不产生锁存
    //==========================================================================
    // IMEM 数据口只读数据：按字对齐索引（const 均为 4 字节对齐访问）
    logic [31:0] imem_dread;
    assign imem_dread = imem_mem[dmem_addr[31:2]];

    always_comb begin
        dmem_rdata = 32'b0;
        if (clint_sel)
            dmem_rdata = clint_rdata;       // CLINT 读数据
        else if (dmem_sel)
            dmem_rdata = dmem_read_raw;    // DMEM 读数据
        else if (uart_sel)
            dmem_rdata = uart_rdata;       // UART 状态
        else if (gpo_sel)
            dmem_rdata = gpo;              // GPO 回读
        else if (imem_sel)
            dmem_rdata = imem_dread;       // IMEM 只读数据（代码/常量）
        // 未映射/保留地址：保持默认 0
    end

endmodule
