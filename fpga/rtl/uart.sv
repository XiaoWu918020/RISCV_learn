//==============================================================================
// File        : uart.sv
// Module      : uart —— 极简内存映射 UART（发送为主，8N1）
// Description : 为无 UART 的 SoC 提供可观测输出。固件轮询状态位等待发送器
//               空闲，再向数据寄存器写入字符即启动一次发送。
//
//   寄存器映射（相对 UART 基址，当前仅用一个寄存器）：
//     offset 0x00  TDR/STATUS
//       写：bit[7:0] 为待发送字符（写脉冲启动发送）
//       读：bit0 = tx_ready（1=发送器空闲，可写下一个字符）
//
//   帧格式：1 起始位(低) + 8 数据位(低位在前) + 1 停止位(高)，空闲为高。
//   波特率由 CLK_FREQ/BAUD_RATE 分频得到，默认 100MHz 下 115200。
//==============================================================================
module uart #(
    parameter int CLK_FREQ  = 100_000_000,   // 输入时钟频率（Hz）
    parameter int BAUD_RATE = 115200         // 波特率
) (
    input  logic        clk,                 // 系统时钟
    input  logic        rst_n,               // 异步低复位

    // 寄存器访问
    input  logic [3:0]  reg_addr_i,          // 寄存器字节偏移（当前仅译码 0x0）
    input  logic [31:0] reg_wdata_i,         // 写数据
    input  logic        reg_we_i,            // 写脉冲
    output logic [31:0] reg_rdata_o,         // 读数据

    // 串行发送
    output logic        tx_o                 // UART TX（接板级串口芯片 RXD）
);

    // 每比特占用的时钟周期数
    localparam int BAUD_DIV = CLK_FREQ / BAUD_RATE;

    // 发送状态
    typedef enum logic [1:0] {
        ST_IDLE = 2'd0,   // 空闲
        ST_START = 2'd1,  // 起始位
        ST_DATA = 2'd2,   // 数据位
        ST_STOP = 2'd3    // 停止位
    } tx_state_t;

    tx_state_t   state;
    logic [15:0] baud_cnt;   // 波特率分频计数
    logic [2:0]  bit_cnt;    // 已发送数据位计数
    logic [7:0]  shift;      // 发送移位寄存器
    logic        tx_ready;   // 发送器空闲标志

    // 波特率节拍：计数到 (BAUD_DIV-1) 归零
    logic baud_tick;
    assign baud_tick = (baud_cnt == BAUD_DIV - 1);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= ST_IDLE;
            baud_cnt <= 16'b0;
            bit_cnt  <= 3'b0;
            shift    <= 8'b0;
            tx_o     <= 1'b1;          // 复位后总线空闲为高
            tx_ready <= 1'b1;
        end else begin
            // 空闲态收到写命令：锁存字符并启动
            if (state == ST_IDLE && reg_we_i) begin
                shift    <= reg_wdata_i[7:0];
                state    <= ST_START;
                tx_ready <= 1'b0;
                baud_cnt <= 16'b0;
            end else begin
                // 波特率分频
                if (baud_tick) baud_cnt <= 16'b0;
                else           baud_cnt <= baud_cnt + 16'd1;

                if (baud_tick) begin
                    unique case (state)
                        ST_START: begin
                            tx_o    <= 1'b0;          // 起始位
                            bit_cnt <= 3'b0;
                            state   <= ST_DATA;
                        end
                        ST_DATA: begin
                            tx_o <= shift[bit_cnt];   // 数据位，LSB 先出
                            if (bit_cnt == 3'd7)
                                state <= ST_STOP;
                            else
                                bit_cnt <= bit_cnt + 3'd1;
                        end
                        ST_STOP: begin
                            tx_o     <= 1'b1;         // 停止位
                            state    <= ST_IDLE;
                            tx_ready <= 1'b1;
                        end
                        default: ;                    // IDLE 保持
                    endcase
                end
            end
        end
    end

    // 寄存器读：仅提供 tx_ready 状态位
    always_comb begin
        reg_rdata_o = 32'b0;
        if (reg_addr_i == 4'h0) begin
            reg_rdata_o[0] = tx_ready;
        end
    end

endmodule
