//==============================================================================
// tb_uart_unit.sv —— uart 模块单元测试（25MHz / 115200）
// 直接驱动 uart：轮询 tx_ready 后写两个字符，用内置 RX 解码 TX，核对结果。
//==============================================================================
`timescale 1ns/1ps

module tb_uart_unit;

    localparam int CLK_FREQ  = 25_000_000;
    localparam int BAUD      = 115200;
    localparam int BIT_NS    = (1_000_000_000 / BAUD);   // 每比特 ns

    logic clk, rst_n;
    logic [3:0]  addr;
    logic [31:0] wdata, rdata;
    logic        we;
    logic        tx;

    initial clk = 1'b0;
    always #20 clk = ~clk;   // 40ns = 25MHz

    uart #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD)) dut (
        .clk(clk), .rst_n(rst_n),
        .reg_addr_i(addr), .reg_wdata_i(wdata),
        .reg_we_i(we), .reg_rdata_o(rdata), .tx_o(tx)
    );

    //---------------- 驱动：发两个字符 ----------------
    initial begin
        addr = 4'h0; we = 1'b0; wdata = 32'b0;
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (3) @(posedge clk);

        send_char(8'h41);   // 'A'
        send_char(8'h42);   // 'B'
        send_char(8'h55);   // 'U'

        repeat (BIT_NS*12) #1;
        $display("==== UART UNIT TEST DONE, received %0d bytes ====", n_rx);
        if (n_rx == 3 && ok_rx == 3)
            $display("==== UART UNIT TEST PASSED ====");
        else
            $display("==== UART UNIT TEST FAILED ok=%0d/%0d ====", ok_rx, n_rx);
        $finish;
    end

    task automatic send_char(input logic [7:0] c);
        begin
            wait (rdata[0] == 1'b1);          // 等 tx_ready
            @(posedge clk);
            wdata = {24'b0, c};
            we    = 1'b1;
            @(posedge clk);
            we    = 1'b0;
            wdata = 32'b0;
        end
    endtask

    //---------------- 内置 RX：监听 tx 解码 ----------------
    integer n_rx = 0, ok_rx = 0;
    logic [7:0] rx_byte;
    int i;

    initial begin
        forever begin
            @(negedge tx);                    // 起始位下降沿
            #(BIT_NS/2);
            if (tx === 1'b0) begin            // 确认是有效起始位
                #(BIT_NS/2);
                for (i = 0; i < 8; i++) begin
                    #BIT_NS;
                    rx_byte[i] = tx;          // LSB 先收
                end
                #BIT_NS;                      // 停止位
                n_rx = n_rx + 1;
                $display("[RX] byte%0d = 0x%02x", n_rx, rx_byte);
                if ((n_rx==1 && rx_byte==8'h41) ||
                    (n_rx==2 && rx_byte==8'h42) ||
                    (n_rx==3 && rx_byte==8'h55))
                    ok_rx = ok_rx + 1;
            end
        end
    end

    initial begin
        #20_000_000 $display("GLOBAL TIMEOUT"); $finish;
    end

endmodule
