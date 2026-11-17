//==============================================================================
// File        : tb_riscv_soc.sv
// Description : riscv_soc 顶层 testbench。加载 timer.hex（由 timer.s 经
//               riscv_as.py 汇编生成），验证软件经 sw/lw 配置 mtimecmp 后，
//               核能够进入机器定时器中断并在处理程序中置位 hit、记录 mcause。
//               主程序写 done 后比对 DMEM 结果，输出 PASS/FAIL。
// 仿真命令    : 见 README.md
//==============================================================================
`timescale 1ns/1ps

module tb_riscv_soc;

    //--------------------------------------------------------------------------
    // 时钟与复位
    //--------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    //--------------------------------------------------------------------------
    // 例化 SoC（指定本测试固件，无外部中断）
    //--------------------------------------------------------------------------
    riscv_soc #(
        .HEX_FILE ("timer.hex")
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

    //--------------------------------------------------------------------------
    // 等待 done（DMEM 字索引 2），带超时保护
    //--------------------------------------------------------------------------
    initial begin
        wait (rst_n == 1'b1);
        for (int t = 0; t < 20000; t++) begin
            @(posedge clk);
            if (u_soc.dmem_mem[2] === 32'd1) begin
                check_result();
                $finish;
            end
        end
        $display("FAIL: 仿真超时，未观察到定时器中断完成");
        $finish;
    end

    //--------------------------------------------------------------------------
    // 结果检查：hit 应为 1，mcause 应为机器定时器中断 0x80000007
    //--------------------------------------------------------------------------
    task check_result();
        int errors;
        begin
            errors = 0;

            if (u_soc.dmem_mem[0] !== 32'd1) begin
                $display("FAIL: hit 期望 1，实际 0x%08x", u_soc.dmem_mem[0]);
                errors++;
            end

            if (u_soc.dmem_mem[1] !== 32'h8000_0007) begin
                $display("FAIL: mcause 期望 0x80000007，实际 0x%08x",
                         u_soc.dmem_mem[1]);
                errors++;
            end

            if (errors == 0)
                $display("==== TIMER IRQ TEST PASSED: mtimecmp 配置并进入定时器中断 ====");
            else
                $display("==== TIMER IRQ TEST FAILED: %0d 项不匹配 ====", errors);
        end
    endtask

endmodule
