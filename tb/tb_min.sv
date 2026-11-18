//==============================================================================
// File        : tb_min.sv
// Description : 最小固件（min.hex）仿真：例化真实 riscv_soc_fpga，监测 GPO 是否
//               发生翻转。看到若干次 GPO 变化即判定最小 CPU 通路（取指/执行/sw）
//               正确；带全局超时保护。
//   运行       : 在 fpga/baremetal_min/build 下（min.hex 位于该目录）
//==============================================================================
`timescale 1ns/1ps
module tb_min;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;   // 100MHz 加速仿真

    logic [31:0] gpo;
    riscv_soc_fpga #(
        .HEX_FILE ("min.hex")
    ) u_soc (
        .clk     (clk),
        .rst_n   (rst_n),
        .ext_irq (1'b0),
        .uart_tx (),
        .gpo_o   (gpo)
    );

    // 释放复位
    initial begin
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    // 监测 GPO 翻转
    initial begin
        int changes;
        logic [31:0] prev;
        changes = 0;
        prev = 32'b0;
        wait (rst_n == 1'b1);

        // 最多仿真 2,000,000 周期，要求至少看到 3 次 GPO 变化
        while (changes < 3) begin
            @(posedge clk);
            if (gpo !== prev) begin
                $display("[GPO] = 0x%08x @%0t", gpo, $time);
                changes++;
                prev = gpo;
            end
        end

        $display("==== MIN FW TEST PASSED: GPO 翻转 %0d 次 ====", changes);
        $finish;
    end

    // 全局超时
    initial begin
        wait (rst_n == 1'b1);
        repeat (2000000) @(posedge clk);
        $display("==== MIN FW TEST FAILED: 超时 gpo=0x%08x ====", gpo);
        $finish;
    end

endmodule
