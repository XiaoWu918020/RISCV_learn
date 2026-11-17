//==============================================================================
// File        : tb_freertos.sv
// Description : FreeRTOS 调度 testbench。在 build 目录运行（firmware.hex 位于
//               该目录），通过 DMEM 最前的 g_probe（.probe 段，dmem_mem[0..3]）
//               观测调度行为：
//                 [0] cnt1  任务1运行计数（每 1 tick）
//                 [1] cnt2  任务2运行计数（每 2 tick）
//                 [2] alive 调度器已启动标志
//                 [3] err   错误标志（须保持 0）
//               先等 alive 置位，再在两个时间点采样，确认两任务计数均增长，
//               以此证明任务调度与上下文切换有效。
// 仿真命令    : 见 README.md / freertos_app 下说明
//==============================================================================
`timescale 1ns/1ps

module tb_freertos;

    //--------------------------------------------------------------------------
    // 时钟与复位
    //--------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    //--------------------------------------------------------------------------
    // 例化 SoC（固件为 build/firmware.hex，无外部中断）
    //--------------------------------------------------------------------------
    riscv_soc #(
        .HEX_FILE ("firmware.hex")
    ) u_soc (
        .clk     (clk),
        .rst_n   (rst_n),
        .ext_irq (1'b0)
    );

    //--------------------------------------------------------------------------
    // 复位序列
    //--------------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    // g_probe 在 dmem_mem 中的字索引
    localparam int P_CNT1  = 0;
    localparam int P_CNT2  = 1;
    localparam int P_ALIVE = 2;
    localparam int P_ERR   = 3;

    //--------------------------------------------------------------------------
    // 主检查流程
    //--------------------------------------------------------------------------
    initial begin
        int t1a, t2a, t1b, t2b;
        int cycles;
        int errors;

        errors = 0;
        cycles = 0;

        wait( rst_n == 1'b1 );

        // 1. 等待调度器启动（alive 置位），带周期上限
        while( ( u_soc.dmem_mem[P_ALIVE] !== 32'd1 ) && ( cycles < 2000000 ) )
        begin
            @(posedge clk);
            cycles++;
        end

        if( u_soc.dmem_mem[P_ALIVE] !== 32'd1 )
        begin
            $display( "FAIL: 调度器未启动（alive 未置位），cnt1=%0d cnt2=%0d",
                      u_soc.dmem_mem[P_CNT1], u_soc.dmem_mem[P_CNT2] );
            $finish;
        end
        $display( "调度器已启动，用时 %0d 个周期", cycles );

        // 2. 第一次采样
        @(posedge clk);
        t1a = u_soc.dmem_mem[P_CNT1];
        t2a = u_soc.dmem_mem[P_CNT2];

        // 3. 再运行约 10 个 tick（每 tick 100000 周期），使计数充分增长
        repeat( 1000000 ) @(posedge clk);

        t1b = u_soc.dmem_mem[P_CNT1];
        t2b = u_soc.dmem_mem[P_CNT2];

        $display( "任务1计数: %0d -> %0d", t1a, t1b );
        $display( "任务2计数: %0d -> %0d", t2a, t2b );

        // 4. 判定：两任务计数均增长、错误标志为 0、且达到最低调度次数
        if( !( t1b > t1a ) )
        begin
            $display( "FAIL: 任务1计数未增长" );
            errors++;
        end
        if( !( t2b > t2a ) )
        begin
            $display( "FAIL: 任务2计数未增长" );
            errors++;
        end
        if( u_soc.dmem_mem[P_ERR] !== 32'd0 )
        begin
            $display( "FAIL: 错误标志 err=0x%08x", u_soc.dmem_mem[P_ERR] );
            errors++;
        end
        if( t1b < 6 )
        begin
            $display( "FAIL: 任务1调度次数过少 cnt1=%0d", t1b );
            errors++;
        end
        if( t2b < 3 )
        begin
            $display( "FAIL: 任务2调度次数过少 cnt2=%0d", t2b );
            errors++;
        end

        if( errors == 0 )
            $display( "==== FREERTOS TEST PASSED: 两任务均被调度且计数增长，上下文切换正常 ====" );
        else
            $display( "==== FREERTOS TEST FAILED: %0d 项不匹配 ====", errors );

        $finish;
    end

    //--------------------------------------------------------------------------
    // 全局超时兜底
    //--------------------------------------------------------------------------
    initial begin
        wait( rst_n == 1'b1 );
        repeat( 3000000 ) @(posedge clk);
        $display( "FAIL: 全局仿真超时" );
        $finish;
    end

endmodule
