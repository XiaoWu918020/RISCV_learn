//==============================================================================
// File        : tb_diag2.sv
// Description : diag2 启动取指跟踪。只运行 3000 周期，记录 imem_addr / imem_rdata /
//               GPO / UART 写，避免长延时循环导致仿真过慢。
//   运行      : 在 fpga/baremetal_uart/build 下（diag2.hex 位于该目录）
//==============================================================================
`timescale 1ns/1ps

module tb_diag2;

    logic clk = 0;
    logic rst_n;
    logic [31:0] gpo;
    logic uart_tx;
    integer fd;
    integer cycles;
    logic [31:0] prev_addr;
    logic [31:0] prev_gpo;

    always #5 clk = ~clk;

    riscv_soc_fpga #(
        .HEX_FILE ("diag2.hex")
    ) u_soc (
        .clk     (clk),
        .rst_n   (rst_n),
        .ext_irq (1'b0),
        .uart_tx (uart_tx),
        .gpo_o   (gpo)
    );

    initial begin
        fd = $fopen("diag2_trace.txt", "w");
        prev_addr = 32'hffff_ffff;
        prev_gpo  = 32'hffff_ffff;
        cycles = 0;
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles <= cycles + 1;

            if ((u_soc.imem_addr !== prev_addr) || (gpo !== prev_gpo)) begin
                $fdisplay(fd, "cyc=%0d imem_addr=0x%08x instr=0x%08x gpo=0x%08x",
                          cycles, u_soc.imem_addr, u_soc.imem_rdata, gpo);
                $fflush(fd);
                prev_addr <= u_soc.imem_addr;
                prev_gpo  <= gpo;
            end

            if (u_soc.uart_reg_we) begin
                $fdisplay(fd, "cyc=%0d UART_WE data=0x%02x", cycles, u_soc.dmem_wdata[7:0]);
                $fflush(fd);
            end

            if (gpo !== 32'b0) begin
                $fdisplay(fd, "PASS: CPU reached GPO write at cyc=%0d gpo=0x%08x", cycles, gpo);
                $fflush(fd);
                $fclose(fd);
                $finish;
            end

            if (cycles >= 3000) begin
                $fdisplay(fd, "TIMEOUT: no GPO write, last imem_addr=0x%08x instr=0x%08x",
                          u_soc.imem_addr, u_soc.imem_rdata);
                $fflush(fd);
                $fclose(fd);
                $finish;
            end
        end
    end

endmodule
