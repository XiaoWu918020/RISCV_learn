//==============================================================================
// File        : riscv_board.sv
// Module      : riscv_board —— 米联客 MLK-VF02（XCZU15EG）板级顶层
// Description : FPGA 物理顶层，负责把板级资源对接到 FPGA 版 SoC：
//                 1. 100MHz 差分时钟经 IBUFDS 进入 MMCM，分频生成 25MHz 全局时钟
//                 2. 用稳定的 100MHz 输入时钟产生干净的 MMCM 上电复位脉冲，
//                    保证 JTAG 配置 / 冷启动 / 重配置下 MMCM 都能可靠锁定
//                 3. PL 按键先做两级同步，再与 MMCM LOCKED 一起产生复位，
//                    异步断言、同步释放，避免亚稳态
//                 4. 例化 riscv_soc_fpga，把 GPO 接 LED、UART TX 接串口
//               核内含纯组合除法器与异步读分布式 RAM，关键路径较长，100MHz 无法
//               收敛；故系统时钟取 25MHz（周期 40ns），核与 SoC 逻辑保持零改动。
//
//   物理引脚（与硬件管脚表一致，详见 XDC）：
//     PL_CLK_P/N  AL6/AL5  100MHz 差分（DIFF_SSTL12）
//     PL_BUT      A20      按键，按下为低（LVCMOS18，底板有外部上拉）
//     PL_LED1/2   D21/D10  高电平点亮（LVCMOS18）
//     UART_TXD1   J17      PL 串口发送（LVCMOS18）
//==============================================================================
module riscv_board #(
    parameter HEX_FILE    = "hex/firmware.hex", // 固件镜像（综合时可由 Tcl 覆盖为绝对路径）
    parameter STATUS_LEDS = 0                   // 1=诊断灯：LED1=locked，LED2=复位心跳/CPU心跳
) (
    input  logic PL_CLK_P,          // 100MHz 差分时钟正
    input  logic PL_CLK_N,          // 100MHz 差分时钟负
    input  logic PL_BUT,           // PL 按键（按下为低，作手动复位）
    output logic PL_LED1,          // PL LED1
    output logic PL_LED2,          // PL LED2
    output logic FPGA_UART_TXD1    // PL 串口发送
);

    //--------------------------------------------------------------------------
    // 1. 差分时钟输入缓冲（clk_ibuf 为稳定的 100MHz，配置后立即可用）
    //--------------------------------------------------------------------------
    logic clk_ibuf;
    IBUFDS u_ibufds (
        .I  (PL_CLK_P),
        .IB (PL_CLK_N),
        .O  (clk_ibuf)
    );

    //--------------------------------------------------------------------------
    // 2. MMCM 上电复位脉冲：用 100MHz 输入时钟计数，配置后先保持 256 个周期
    //    （约 2.56us）高电平，再拉低，给 MMCM 一个干净、确定的复位脉冲。
    //    计数器从 INIT=0 自由运行，无需额外复位。
    //--------------------------------------------------------------------------
    logic [7:0] por_cnt;
    logic       mmcm_rst;

    initial begin
        por_cnt  = 8'b0;
        mmcm_rst = 1'b1;
    end

    always_ff @(posedge clk_ibuf) begin
        if (por_cnt != 8'hFF) begin
            por_cnt  <= por_cnt + 8'd1;
            mmcm_rst <= 1'b1;
        end else begin
            mmcm_rst <= 1'b0;
        end
    end

    //--------------------------------------------------------------------------
    // 3. MMCM：100MHz -> 25MHz
    //    PFD     = CLKIN1 / DIVCLK_DIVIDE(1)            = 100MHz
    //    VCO     = PFD * CLKFBOUT_MULT_F(10)            = 1000MHz（合法 800~1600）
    //    CLKOUT0 = VCO / CLKOUT0_DIVIDE_F(40)           = 25MHz
    //--------------------------------------------------------------------------
    logic clkfbout;        // MMCM 反馈原始输出
    logic clk_fb;          // 反馈经 BUFG 后回接 CLKFBIN
    logic clk25;           // 25MHz 原始输出
    logic locked;          // MMCM 锁定标志

    MMCME3_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (10.0),     // VCO 倍频系数
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (10.0),     // 输入 100MHz 周期（ns）
        .CLKOUT0_DIVIDE_F   (40.0),     // CLKOUT0 分频 -> 25MHz
        .CLKOUT0_DUTY_CYCLE (0.5),
        .CLKOUT0_PHASE      (0.0),
        .DIVCLK_DIVIDE      (1),
        .REF_JITTER1        (0.010),
        .STARTUP_WAIT       ("FALSE")
    ) u_mmcm (
        .CLKIN1   (clk_ibuf),
        .CLKFBIN  (clk_fb),
        .CLKFBOUT (clkfbout),
        .CLKOUT0  (clk25),
        .LOCKED   (locked),
        .PWRDWN   (1'b0),
        .RST      (mmcm_rst)            // 干净的上电复位脉冲（不再由按键直接驱动）
    );

    // 反馈时钟与系统时钟均走全局时钟缓冲，保证低抖动、低偏斜
    logic clk;          // 25MHz 系统全局时钟（供复位同步器与 SoC 使用）
    BUFG u_bufg_fb  (.I (clkfbout), .O (clk_fb));
    BUFG u_bufg_sys (.I (clk25),    .O (clk));

    //--------------------------------------------------------------------------
    // 4. PL 按键两级同步：异步输入先同步到 25MHz 时钟域，消除亚稳态
    //    but_pressed 为同步后的“按下”指示（高有效）
    //--------------------------------------------------------------------------
    logic but_sync1, but_sync2, but_pressed;

    always_ff @(posedge clk) begin
        but_sync1 <= PL_BUT;
        but_sync2 <= but_sync1;
    end

    assign but_pressed = ~but_sync2;

    // 同步上电复位到 25MHz 域（mmcm_rst 属于 100MHz 域，这里跨域做安全处理）
    logic rst_sync1, rst_sync2, por_rst;

    always_ff @(posedge clk) begin
        rst_sync1 <= mmcm_rst;
        rst_sync2 <= rst_sync1;
    end

    assign por_rst = rst_sync2;

    //--------------------------------------------------------------------------
    // 5. 复位同步器：以下任一条件成立则保持复位，锁定且无复位请求后同步释放
    //      - MMCM 未锁定
    //      - 上电复位仍有效
    //      - PL 按键按下
    //    同步释放避免复位撤销沿的亚稳态。
    //--------------------------------------------------------------------------
    logic [2:0] rst_sync;

    always_ff @(posedge clk) begin
        if (!locked || por_rst || but_pressed)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end

    logic rst_n;
    assign rst_n = rst_sync[2];

    //--------------------------------------------------------------------------
    // 6. SoC 例化（CLK_FREQ 与实际系统时钟一致，UART 据此计算波特率分频）
    //--------------------------------------------------------------------------
    logic [31:0] gpo;
    logic        uart_tx;

    riscv_soc_fpga #(
        .HEX_FILE (HEX_FILE),       // 向下传递固件镜像路径
        .CLK_FREQ (25_000_000)      // 系统时钟 25MHz
    ) u_soc (
        .clk     (clk),
        .rst_n   (rst_n),
        .ext_irq (1'b0),          // 本演示未用外部中断
        .uart_tx (uart_tx),
        .gpo_o   (gpo)
    );

    //--------------------------------------------------------------------------
    // 7. 板级输出连接
    //    正常模式：LED 由固件写 GPO 驱动。
    //    诊断模式：LED1 直接显示 MMCM locked；LED2 在复位期间由硬件计数器
    //              慢闪，复位释放后改由 CPU 的 GPO bit0 驱动。这样无需 ILA
    //              即可区分“MMCM 未锁定 / CPU 仍在复位 / CPU 未写 GPO”。
    //--------------------------------------------------------------------------
    logic [23:0] status_cnt = 24'd0;
    always_ff @(posedge clk)
        status_cnt <= status_cnt + 24'd1;

    generate
        if (STATUS_LEDS != 0) begin : g_status_leds
            assign PL_LED1 = locked;
            assign PL_LED2 = rst_n ? gpo[0] : status_cnt[23];
        end else begin : g_normal_leds
            assign PL_LED1 = gpo[0];
            assign PL_LED2 = gpo[1];
        end
    endgenerate

    assign FPGA_UART_TXD1 = uart_tx;

endmodule
