//==============================================================================
// tb_board_netlist.sv —— 整板综合后仿真：真实 MMCM + 复位 + SoC + diag2 固件
//==============================================================================
`timescale 1ns/1ps

module tb_board_netlist;
    logic PL_CLK_P = 1'b0;
    logic PL_CLK_N = 1'b1;
    logic PL_BUT = 1'b1;
    wire PL_LED1;
    wire PL_LED2;
    wire FPGA_UART_TXD1;
    integer fd;
    integer pc_cycles = 0;

    always #5 begin
        PL_CLK_P = ~PL_CLK_P;
        PL_CLK_N = ~PL_CLK_N;
    end

    riscv_board dut (
        .PL_CLK_P(PL_CLK_P),
        .PL_CLK_N(PL_CLK_N),
        .PL_BUT(PL_BUT),
        .PL_LED1(PL_LED1),
        .PL_LED2(PL_LED2),
        .FPGA_UART_TXD1(FPGA_UART_TXD1)
    );

    initial begin
        fd = $fopen("board_netlist_trace.txt", "w");
        $fdisplay(fd, "START time=%0t", $time);
        $fflush(fd);
        #50000;
        $fdisplay(fd, "END time=%0t LED1=%b LED2=%b UART=%b", $time, PL_LED1, PL_LED2, FPGA_UART_TXD1);
        $fflush(fd);
        $fclose(fd);
        $finish;
    end

    always @(PL_LED1 or PL_LED2) begin
        $fdisplay(fd, "LED time=%0t LED1=%b LED2=%b", $time, PL_LED1, PL_LED2);
        $fflush(fd);
    end

    always @(negedge FPGA_UART_TXD1) begin
        $fdisplay(fd, "UART_NEGEDGE time=%0t", $time);
        $fflush(fd);
    end

    // 综合网表内部取指跟踪：复位释放后前 100 个系统周期
    always @(posedge dut.clk) begin
        if (dut.rst_n && (pc_cycles < 100)) begin
            $fdisplay(fd, "IF cyc=%0d ifid=%08x ifpc=%08x LED2=%b",
                      pc_cycles, dut.u_soc.u_core.ifid_inst,
                      dut.u_soc.u_core.ifid_pc, PL_LED2);
            $fflush(fd);
            pc_cycles = pc_cycles + 1;
        end
    end
endmodule
