//==============================================================================
// File        : tb_riscv_core.sv
// Description : riscv_core 顶层 testbench。
//               加载 test.hex（由 test.s 经 riscv_as.py 汇编生成），运行至
//               程序自循环，然后比对 0x2000 起的 26 项签名，输出 PASS/FAIL。
//               另含 CLINT 驱动：在软件中断使能后触发 msip，并在核进入中断
//               处理程序后清除 msip，完成软件中断的端到端验证。
// 仿真命令    : 见 README.md
//==============================================================================
`timescale 1ns/1ps

module tb_riscv_core;

    import riscv_defines::*;

    //--------------------------------------------------------------------------
    // 时钟与复位
    //--------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    //--------------------------------------------------------------------------
    // 核与存储器之间的接口信号
    //--------------------------------------------------------------------------
    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic [3:0]  dmem_wbe;
    logic        dmem_en;

    // CLINT 存储器映射接口（由中断驱动 task 控制）
    logic [31:0] clint_addr, clint_wdata, clint_rdata;
    logic        clint_we, clint_re;

    //--------------------------------------------------------------------------
    // 例化被测核（无外部中断）
    //--------------------------------------------------------------------------
    riscv_core u_dut (
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
        .ext_irq      (1'b0)
    );

    //--------------------------------------------------------------------------
    // 例化存储器并加载程序
    //--------------------------------------------------------------------------
    imem_model u_imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    dmem_model u_dmem (
        .clk   (clk),
        .addr  (dmem_addr),
        .wdata (dmem_wdata),
        .wbe   (dmem_wbe),
        .en    (dmem_en),
        .rdata (dmem_rdata)
    );

    initial begin
        $readmemh("test.hex", u_imem.mem);
    end

    //--------------------------------------------------------------------------
    // 复位序列
    //--------------------------------------------------------------------------
    initial begin
        rst_n = 1'b0;
        clint_addr = 32'b0; clint_wdata = 32'b0;
        clint_we = 1'b0;  clint_re = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    //--------------------------------------------------------------------------
    // CLINT 单字写驱动（用于触发/清除 msip）
    //--------------------------------------------------------------------------
    task clint_write(input logic [31:0] addr, input logic [31:0] data);
        begin
            @(posedge clk);
            clint_addr  <= addr;
            clint_wdata <= data;
            clint_we    <= 1'b1;
            @(posedge clk);
            clint_addr  <= 32'b0;
            clint_wdata <= 32'b0;
            clint_we    <= 1'b0;
        end
    endtask

    //--------------------------------------------------------------------------
    // 软件中断端到端：使能后触发 msip，进入处理程序后清除
    //--------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        // 等待软件中断使能（mie.MS）且全局中断（mstatus.MIE）打开
        wait (u_dut.u_rf.mie_r[M_INT_MS] == 1'b1 &&
              u_dut.u_rf.mstatus_mie == 1'b1);
        repeat (2) @(posedge clk);
        clint_write(32'h00, 32'h0000_0001);        // msip = 1，触发软件中断
        wait (u_dut.u_rf.mcause_r == CAUSE_S_INT); // 核已进入软件中断
        @(posedge clk);
        clint_write(32'h00, 32'h0000_0000);        // msip = 0，避免重复触发
    end

    //--------------------------------------------------------------------------
    // 等待程序完成（done 标志位于 0x2064），带超时保护
    //--------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        for (int t = 0; t < 20000; t++) begin
            @(posedge clk);
            if (u_dmem.mem[32'h2064 >> 2] === 32'd1) begin
                check_signature();
                $finish;
            end
        end
        $display("FAIL: 仿真超时，程序未正常结束");
        $finish;
    end

    //--------------------------------------------------------------------------
    // 签名比对：26 项 (地址, 期望值)
    //--------------------------------------------------------------------------
    task check_signature();
        // 局部声明统一置于任务开头（兼容 Icarus Verilog）
        int errors;
        logic [31:0] addr_q [0:25];
        logic [31:0] expect_q [0:25];

        begin
            errors = 0;

            addr_q[0]  = 32'h2000; expect_q[0]  = 32'd7;
            addr_q[1]  = 32'h2004; expect_q[1]  = 32'd13;
            addr_q[2]  = 32'h2008; expect_q[2]  = 32'd7;
            addr_q[3]  = 32'h200C; expect_q[3]  = 32'h0000_0055;
            addr_q[4]  = 32'h2010; expect_q[4]  = 32'd10;
            addr_q[5]  = 32'h2014; expect_q[5]  = 32'hFFFF_FFFD;
            addr_q[6]  = 32'h2018; expect_q[6]  = 32'hFFFF_FFE2;
            addr_q[7]  = 32'h201C; expect_q[7]  = 32'hFFFF_FFFD;
            addr_q[8]  = 32'h2020; expect_q[8]  = 32'd1;
            addr_q[9]  = 32'h2024; expect_q[9]  = 32'd42;
            addr_q[10] = 32'h2028; expect_q[10] = 32'hFFFF_FF80;
            addr_q[11] = 32'h202C; expect_q[11] = 32'h0000_0080;
            addr_q[12] = 32'h2030; expect_q[12] = 32'd0;
            addr_q[13] = 32'h2034; expect_q[13] = 32'd1;
            addr_q[14] = 32'h2038; expect_q[14] = 32'd1;
            addr_q[15] = 32'h203C; expect_q[15] = 32'hFFFF_FFFF;
            addr_q[16] = 32'h2040; expect_q[16] = 32'h1234_5678;
            addr_q[17] = 32'h2044; expect_q[17] = 32'h4000_1100;
            addr_q[18] = 32'h2048; expect_q[18] = 32'h0000_0088;
            addr_q[19] = 32'h204C; expect_q[19] = 32'h0000_0080;
            addr_q[20] = 32'h2050; expect_q[20] = 32'd1;
            addr_q[21] = 32'h2054; expect_q[21] = 32'd11;
            addr_q[22] = 32'h2058; expect_q[22] = 32'd77;
            addr_q[23] = 32'h205C; expect_q[23] = 32'h8000_0003;
            addr_q[24] = 32'h2060; expect_q[24] = 32'd88;
            addr_q[25] = 32'h2064; expect_q[25] = 32'd1;

            for (int i = 0; i < 26; i++) begin
                if (u_dmem.mem[addr_q[i] >> 2] !== expect_q[i]) begin
                    $display("FAIL: addr=0x%08x got=0x%08x expect=0x%08x",
                             addr_q[i], u_dmem.mem[addr_q[i] >> 2], expect_q[i]);
                    errors++;
                end
            end

            if (errors == 0)
                $display("==== TEST PASSED: 全部 26 项签名校验通过 ====");
            else
                $display("==== TEST FAILED: %0d 项签名不匹配 ====", errors);
        end
    endtask

endmodule
