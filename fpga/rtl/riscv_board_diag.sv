//==============================================================================
// File        : riscv_board_diag.sv
// Module      : riscv_board_diag —— 板级硬件 Bring-up 诊断顶层（不依赖 CPU/固件）
// Description : 用于在不依赖 riscv_core 与固件的前提下，验证最底层板级通路：
//                 1. 100MHz 差分时钟 + IBUFDS + MMCM 能否产生 25MHz 并 LOCK
//                 2. 25MHz 时钟是否真正到达逻辑（自由计数器心跳）
//                 3. LED 物理引脚 / 电平 / 极性是否正确
//
//   判读（烧录后直接看两个 LED）：
//     PL_LED1 常亮 ：MMCM 已 LOCK；常灭：MMCM 未锁定（时钟/MMCM 配置问题）
//     PL_LED2 闪烁 ：25MHz 时钟在跑；不闪：时钟/路由问题
//     两者都不亮   ：引脚/LED 极性/供电问题（与逻辑无关）
//   正常应看到 LED1 常亮、LED2 约 1Hz 闪烁。
//==============================================================================
module riscv_board_diag (
    input  logic PL_CLK_P,          // 100MHz 差分时钟正
    input  logic PL_CLK_N,          // 100MHz 差分时钟负
    input  logic PL_BUT,           // PL 按键（本诊断仅用于 MMCM 复位）
    output logic PL_LED1,          // 诊断灯1：MMCM LOCKED
    output logic PL_LED2,          // 诊断灯2：25MHz 心跳
    output logic FPGA_UART_TXD1    // 串口发送（诊断中固定为空闲高）
);

    //--------------------------------------------------------------------------
    // 1. 差分时钟输入缓冲
    //--------------------------------------------------------------------------
    logic clk_ibuf;
    IBUFDS u_ibufds (
        .I  (PL_CLK_P),
        .IB (PL_CLK_N),
        .O  (clk_ibuf)
    );

    //--------------------------------------------------------------------------
    // 2. MMCM：100MHz -> 25MHz（参数与正式顶层一致）
    //--------------------------------------------------------------------------
    logic clkfbout, clk_fb, clk25, locked, clk;

    MMCME3_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKFBOUT_MULT_F    (10.0),
        .CLKFBOUT_PHASE     (0.0),
        .CLKIN1_PERIOD      (10.0),
        .CLKOUT0_DIVIDE_F   (40.0),
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
        .RST      (~PL_BUT)
    );

    BUFG u_bufg_fb  (.I (clkfbout), .O (clk_fb));
    BUFG u_bufg_sys (.I (clk25),    .O (clk));

    //--------------------------------------------------------------------------
    // 3. 诊断灯1：直接显示 MMCM LOCKED
    //--------------------------------------------------------------------------
    assign PL_LED1 = locked;

    //--------------------------------------------------------------------------
    // 4. 诊断灯2：自由运行慢计数器，约 1Hz 翻转（0.5s = 12,500,000 周期）
    //    不依赖复位，只要 clk 在跳就闪，最直接反映时钟是否到达逻辑。
    //--------------------------------------------------------------------------
    logic [23:0] cnt;
    logic        led2;

    always_ff @(posedge clk) begin
        if (cnt == 24'd12_499_999) begin
            cnt  <= 24'b0;
            led2 <= ~led2;
        end else begin
            cnt <= cnt + 24'd1;
        end
    end

    assign PL_LED2 = led2;

    //--------------------------------------------------------------------------
    // 5. 串口 TX 固定为空闲高，避免悬空
    //--------------------------------------------------------------------------
    assign FPGA_UART_TXD1 = 1'b1;

endmodule
