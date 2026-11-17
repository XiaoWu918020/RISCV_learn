`timescale 1ns/1ps
module tb_debug;
    logic clk, rst_n;
    bit trig;
    int cnt;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    riscv_soc #(.HEX_FILE("firmware.hex")) u_soc
        (.clk(clk), .rst_n(rst_n), .ext_irq(1'b0));

    initial begin
        rst_n = 1'b0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    initial begin
        wait(rst_n == 1'b1);
        forever begin
            @(posedge clk);
            if (!trig && u_soc.u_core.u_ex.exc_enter_o &&
                (u_soc.u_core.u_ex.exc_cause_o == 32'h80000007) &&
                (u_soc.u_core.u_clint.mtime_r > 339000) &&
                (u_soc.u_core.u_clint.mtime_r < 340000))
                trig = 1'b1;

            if (trig) begin
                $display("stall=%0d pcsrc=%0d pcnew=0x%08x ifpc=0x%08x exvalid=%0d enter=%0d",
                         u_soc.u_core.stall,
                         u_soc.u_core.pc_sel,
                         u_soc.u_core.pc_new,
                         u_soc.u_core.u_if.pc_r,
                         u_soc.u_core.u_ex.valid_i,
                         u_soc.u_core.u_ex.exc_enter_o);
                cnt++;
                if (cnt > 18) $finish;
            end
        end
    end
endmodule
