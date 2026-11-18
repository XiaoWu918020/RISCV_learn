//==============================================================================
// File        : tb_fpga_rtl.sv
// Description : 精确复现 FPGA RTL（riscv_soc_fpga + fpga_ram）的 FreeRTOS 仿真。
//               与 tb_freertos 的区别：不例化仿真用 riscv_soc，而是例化实际上板
//               的 riscv_soc_fpga，用于排查“仿真过、上板不过”是否源于两套 SoC
//               实现差异。通过层次引用 u_dmem.mem 观察 g_probe，并监测 gpo_o。
//   运行      : 在 freertos_app/build 下（firmware.hex 位于该目录）
//==============================================================================
`timescale 1ns/1ps

module tb_fpga_rtl;

    logic clk;
    logic rst_n;

    initial clk = 1'b0;
    always #5 clk = ~clk;   // 功能与时频无关，100MHz 加速仿真

    // 例化真实上板 SoC（参数默认值与 build.tcl 一致）
    riscv_soc_fpga #(
        .HEX_FILE ("firmware.hex")
    ) u_soc (
        .clk     (clk),
        .rst_n   (rst_n),
        .ext_irq (1'b0),
        .uart_tx (),
        .gpo_o   (gpo)
    );

    logic [31:0] gpo;

    initial begin
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    // g_probe 位于 DMEM 偏移 0（fpga_ram 内 mem 数组）
    localparam int P_CNT1 = 0, P_CNT2 = 1, P_ALIVE = 2, P_ERR = 3;

    // 监测 GPO（LED）写动作
    initial begin
        logic [31:0] prev;
        prev = 32'b0;
        wait (rst_n == 1'b1);
        forever begin
            @(posedge clk);
            if (gpo != prev) begin
                $display("[GPO] gpo_o=0x%08x @%0t", gpo, $time);
                prev = gpo;
            end
        end
    end

    initial begin
        int t1a, t2a, t1b, t2b, cycles, errors;
        errors = 0; cycles = 0;
        wait (rst_n == 1'b1);

        while ((u_soc.u_dmem.mem[P_ALIVE] !== 32'd1) && (cycles < 2000000)) begin
            @(posedge clk); cycles++;
        end
        if (u_soc.u_dmem.mem[P_ALIVE] !== 32'd1) begin
            $display("FAIL: 调度器未启动 cnt1=%0d cnt2=%0d gpo=0x%08x",
                     u_soc.u_dmem.mem[P_CNT1], u_soc.u_dmem.mem[P_CNT2], gpo);
            $finish;
        end
        $display("调度器已启动，用时 %0d 周期", cycles);

        @(posedge clk);
        t1a = u_soc.u_dmem.mem[P_CNT1];
        t2a = u_soc.u_dmem.mem[P_CNT2];

        repeat (2000000) @(posedge clk);
        t1b = u_soc.u_dmem.mem[P_CNT1];
        t2b = u_soc.u_dmem.mem[P_CNT2];
        $display("任务1: %0d -> %0d", t1a, t1b);
        $display("任务2: %0d -> %0d", t2a, t2b);
        $display("DEBUG: mtime=%0d mtimecmp=%0d mip=0x%08x MIE=%b mie_r=0x%08x pc=0x%08x",
                 u_soc.u_core.u_clint.mtime_r, u_soc.u_core.u_clint.mtimecmp_r,
                 u_soc.u_core.u_clint.mip_r, u_soc.u_core.u_rf.mstatus_mie,
                 u_soc.u_core.u_rf.mie_r, u_soc.u_core.u_if.pc_r);

        if (!(t1b > t1a)) errors++;
        if (!(t2b > t2a)) errors++;
        if (u_soc.u_dmem.mem[P_ERR] !== 32'd0) errors++;
        if (t1b < 60) errors++;
        if (t2b < 25) errors++;

        if (errors == 0)
            $display("==== FPGA-RTL TEST PASSED: gpo=0x%08x ====", gpo);
        else
            $display("==== FPGA-RTL TEST FAILED: %0d 项 ====", errors);
        $finish;
    end

    initial begin
        wait (rst_n == 1'b1);
        repeat (4000000) @(posedge clk);
        $display("FAIL: 全局超时 gpo=0x%08x", gpo);
        $finish;
    end

    // FreeRTOS 仅使用 ECALL(11) 主动切换任务；其余同步异常均立即失败。
    always @(posedge clk) begin
        if (rst_n && u_soc.u_core.exc_enter &&
            !u_soc.u_core.exc_cause[31] && (u_soc.u_core.exc_cause != 32'd11)) begin
            $display("UNEXPECTED EXCEPTION: mcause=0x%08x mepc=0x%08x mtval=0x%08x",
                     u_soc.u_core.exc_cause, u_soc.u_core.exc_epc,
                     u_soc.u_core.exc_tval);
            $finish;
        end
    end

endmodule
