//==============================================================================
// File        : ex_unit.sv
// Module      : ex_unit —— 三级流水线：执行单元（EX）
// Description : 对应框图 EX_UNIT，以控制单元 cu 为主控，例化三个运算部件：
//                 alu ：基础整数运算
//                 mul ：RV32M 乘法
//                 div ：RV32M 除法/取余
//               cu 负责：
//                 - 操作数选择与运算结果汇总
//                 - load/store 地址生成、字节对齐、写掩码与符号扩展
//                 - 条件分支判定与跳转目标计算
//                 - CSR 指令执行、同步异常检测、中断响应与 mret
//                 - 写回数据选择及流水线重定向/冲刷
//               本模块为纯组合逻辑，寄存器写回在时钟沿由 rf_unit 完成。
//==============================================================================
`include "riscv_types.svh"
module ex_unit (
    // ID/EX 寄存器输入
    input  logic [31:0] pc_i,          // 当前执行指令 PC
    input  logic        valid_i,       // 有效指令（0=气泡）
    input  ctrl_bus_t   ctrl_i,        // 打包控制字段
    input  logic [4:0]  rs1_i,
    input  logic [4:0]  rs2_i,
    input  logic [4:0]  rd_i,
    input  logic [31:0] reg_a_i,       // 操作数 A（ID 级已转发）
    input  logic [31:0] reg_b_i,       // 操作数 B（ID 级已转发）
    input  logic [31:0] imm_i,         // 立即数
    input  logic [31:0] inst_i,        // 原始指令

    // ID 级信息（中断保存精确断点用）
    input  logic [31:0] id_pc_i,       // ID 级指令 PC
    input  logic        id_valid_i,    // ID 级是否有效

    // 数据存储器接口
    output logic [31:0] dmem_addr_o,
    output logic [31:0] dmem_wdata_o,
    output logic [3:0]  dmem_wbe_o,    // 字节写使能（高有效）
    output logic        dmem_en_o,
    input  logic [31:0] dmem_rdata_i,

    // 写回输出（送往顶层/寄存器堆，并供 ID 级转发冒险）
    output logic        ex_wreg_o,
    output logic [4:0]  ex_rd_o,
    output logic [31:0] ex_wdata_o,
    output logic        ex_mem_read_o,

    // CSR / 异常接口（与 rf_unit 相连）
    output logic [11:0] csr_addr_o,
    output logic [1:0]  csr_op_o,
    output logic [31:0] csr_wdata_o,
    input  logic [31:0] csr_rdata_i,
    output logic        ex_csr_we_o,
    output logic        exc_enter_o,
    output logic [31:0] exc_cause_o,
    output logic [31:0] exc_tval_o,
    output logic [31:0] exc_epc_o,
    output logic        mret_o,
    input  logic [31:0] ret_pc_i,      // mret 返回地址
    input  logic [31:0] mtvec_i,       // 异常入口向量

    // 中断请求（来自 rf_unit）
    input  logic        irq_req_i,
    input  logic [31:0] irq_cause_i,

    // 流水线重定向
    output logic        pc_sel_o,      // 1=PC 跳转到 pc_new_o
    output logic [31:0] pc_new_o,
    output logic        flush_o,       // 冲刷 IF/ID 与 ID/EX

    output logic        instr_ret_o    // 指令提交脉冲
);

    import riscv_defines::*;

    //==========================================================================
    // 1. 运算部件输入选择
    //      对所有经过主 ALU 的算术 / 逻辑 / 访存地址运算
    //      a 在 PC 与 rs1 间二选一、b 在 imm 与 rs2 间二选一；
    //      LUI、跳转目标地址、CSR、独立乘除是例外
    //==========================================================================
    logic [31:0] alu_a, alu_b;
    assign alu_a = ctrl_i.auipc ? pc_i : reg_a_i;          // auipc 以 PC 为基址
    assign alu_b = ctrl_i.alu_src ? imm_i : reg_b_i;       // 立即数/寄存器选择

    //--------------------------------------------------------------------------
    // 运算部件例化
    //--------------------------------------------------------------------------
    logic [31:0] alu_y, mul_y, div_y;

    alu u_alu (
        .a      (alu_a),
        .b      (alu_b),
        .alu_op (ctrl_i.alu_op),
        .y      (alu_y)
    );

    mul u_mul (
        .a      (reg_a_i),
        .b      (reg_b_i),
        .funct3 (ctrl_i.funct3),
        .y      (mul_y)
    );

    div u_div (
        .a      (reg_a_i),
        .b      (reg_b_i),
        .funct3 (ctrl_i.funct3),
        .y      (div_y)
    );

    //==========================================================================
    // 2. 访存地址与非对齐检测
    //==========================================================================
    assign dmem_addr_o  = alu_y;   // 地址 = 基址 + 偏移（ALU 加法结果）

    logic load_misalign, store_misalign; //加载地址错位标志，存储地址错位标志
    assign load_misalign  = ctrl_i.mem_read &&
                            ((ctrl_i.mem_size == MEM_HALF && dmem_addr_o[0]) ||
                             (ctrl_i.mem_size == MEM_WORD && (|dmem_addr_o[1:0])));
    assign store_misalign = ctrl_i.mem_write &&
                            ((ctrl_i.mem_size == MEM_HALF && dmem_addr_o[0]) ||
                             (ctrl_i.mem_size == MEM_WORD && (|dmem_addr_o[1:0])));

    //--------------------------------------------------------------------------
    // store：写数据按地址字节对齐，并生成字节写使能
    //--------------------------------------------------------------------------
    always_comb begin
        unique case (ctrl_i.mem_size)
            MEM_BYTE: begin
                dmem_wbe_o   = ctrl_i.mem_write ? (4'b0001 << dmem_addr_o[1:0]) : 4'b0000;
                dmem_wdata_o = reg_b_i[7:0] << {dmem_addr_o[1:0], 3'b000};
            end
            MEM_HALF: begin
                dmem_wbe_o   = ctrl_i.mem_write ? (4'b0011 << {dmem_addr_o[1], 1'b0}) : 4'b0000;
                dmem_wdata_o = reg_b_i[15:0] << {dmem_addr_o[1], 4'b0000};
            end
            MEM_WORD: begin
                dmem_wbe_o   = ctrl_i.mem_write ? 4'b1111 : 4'b0000;
                dmem_wdata_o = reg_b_i;
            end
            default: begin
                dmem_wbe_o   = 4'b0000;
                dmem_wdata_o = 32'b0;
            end
        endcase
    end

    //--------------------------------------------------------------------------
    // load：按地址取出字节/半字并做符号或零扩展
    //--------------------------------------------------------------------------
    logic [7:0]  lb_raw;
    logic [15:0] lh_raw;
    logic [31:0] load_data;

    always_comb begin
        unique case (dmem_addr_o[1:0])
            2'b00: lb_raw = dmem_rdata_i[7:0];
            2'b01: lb_raw = dmem_rdata_i[15:8];
            2'b10: lb_raw = dmem_rdata_i[23:16];
            2'b11: lb_raw = dmem_rdata_i[31:24];
        endcase
    end

    always_comb begin
        unique case (dmem_addr_o[1])
            1'b0: lh_raw = dmem_rdata_i[15:0];
            1'b1: lh_raw = dmem_rdata_i[31:16];
        endcase
    end

    always_comb begin
        unique case (ctrl_i.mem_size)
            MEM_BYTE:
                load_data = ctrl_i.mem_unsigned ? {24'b0, lb_raw}
                                                : {{24{lb_raw[7]}}, lb_raw};
            MEM_HALF:
                load_data = ctrl_i.mem_unsigned ? {16'b0, lh_raw}
                                                : {{16{lh_raw[15]}}, lh_raw};
            MEM_WORD:
                load_data = dmem_rdata_i;
            default:
                load_data = 32'b0;
        endcase
    end

    //==========================================================================
    // 3. 条件分支判定与跳转目标
    //==========================================================================
    logic branch_taken;

    always_comb begin
        unique case (ctrl_i.funct3)
            3'b000: branch_taken = (reg_a_i == reg_b_i);                     // beq
            3'b001: branch_taken = (reg_a_i != reg_b_i);                     // bne
            3'b100: branch_taken = ($signed(reg_a_i) <  $signed(reg_b_i));  // blt
            3'b101: branch_taken = ($signed(reg_a_i) >= $signed(reg_b_i));  // bge
            3'b110: branch_taken = (reg_a_i <  reg_b_i);                     // bltu
            3'b111: branch_taken = (reg_a_i >= reg_b_i);                     // bgeu
            default: branch_taken = 1'b0;
        endcase
        branch_taken = ctrl_i.branch && branch_taken;
    end

    logic [31:0] branch_target, jalr_target;
    assign branch_target = pc_i + imm_i;
    assign jalr_target   = (reg_a_i + imm_i) & ~32'b1;  // jalr 目标最低位清零

    //==========================================================================
    // 4. 同步异常检测与原因/值生成
    //==========================================================================
    logic sync_exc;
    assign sync_exc = valid_i && (ctrl_i.illegal || ctrl_i.ecall || ctrl_i.ebreak ||
                                  load_misalign || store_misalign);

    logic [31:0] sync_cause, sync_tval;
    always_comb begin
        if (ctrl_i.illegal) begin
            sync_cause = CAUSE_ILLEGAL_INST;
            sync_tval  = inst_i;
        end else if (ctrl_i.ecall) begin
            sync_cause = CAUSE_ECALL_M;
            sync_tval  = 32'b0;
        end else if (ctrl_i.ebreak) begin
            sync_cause = CAUSE_BREAKPOINT;
            sync_tval  = 32'b0;
        end else if (load_misalign) begin
            sync_cause = CAUSE_LOAD_MISALIGN;
            sync_tval  = dmem_addr_o;
        end else begin  // store_misalign
            sync_cause = CAUSE_STORE_MISALIGN;
            sync_tval  = dmem_addr_o;
        end
    end

    //==========================================================================
    // 5. 中断响应（异步，在有效指令提交边界采样）
    //==========================================================================
    logic irq_taken;
    assign irq_taken = valid_i && irq_req_i && !sync_exc && !ctrl_i.mret;

    //--------------------------------------------------------------------------
    // 异常/中断总入口
    //--------------------------------------------------------------------------
    assign exc_enter_o = sync_exc || irq_taken;
    assign exc_cause_o = sync_exc ? sync_cause : irq_cause_i;
    assign exc_tval_o  = sync_exc ? sync_tval  : 32'b0;
    // 同步异常断点=当前指令。异步中断时当前 EX 指令仍提交，因此断点必须是
    // 它之后的实际执行地址：控制转移指令不能简单取 pc+4，否则 ret/jal/分支
    // 与中断同拍时，mret 会错误返回顺序路径（例如从函数 epilogue 中间继续）。
    logic [31:0] irq_next_pc;
    always_comb begin
        if (ctrl_i.jump)
            irq_next_pc = branch_target;
        else if (ctrl_i.jalr)
            irq_next_pc = jalr_target;
        else if (branch_taken)
            irq_next_pc = branch_target;
        else if (id_valid_i)
            irq_next_pc = id_pc_i;
        else
            irq_next_pc = pc_i + 32'd4;
    end
    assign exc_epc_o = sync_exc ? pc_i : irq_next_pc;

    //==========================================================================
    // 6. CSR 指令输出
    //==========================================================================
    assign csr_addr_o  = ctrl_i.csr_addr;
    assign csr_op_o    = valid_i ? ctrl_i.csr_op : CSR_NONE;
    // 立即数版本：写数据为零扩展的 zimm（rs1 字段）；否则取 rs1 寄存器值
    assign csr_wdata_o = ctrl_i.csr_imm ? {27'b0, rs1_i} : reg_a_i;
    assign ex_csr_we_o = valid_i && (ctrl_i.csr_op != CSR_NONE);
    assign mret_o      = valid_i && ctrl_i.mret;

    //==========================================================================
    // 7. 重定向仲裁（优先级：异常/中断 > mret > jal > jalr > 条件分支）
    //==========================================================================
    logic [31:0] mtvec_base, exc_target;
    assign mtvec_base = {mtvec_i[31:2], 2'b0};
    // vectored 模式仅对中断生效：base + 4*cause
    assign exc_target = (irq_taken && mtvec_i[0])
                        ? (mtvec_base + {26'b0, irq_cause_i[3:0], 2'b0})
                        : mtvec_base;

    always_comb begin
        pc_sel_o = 1'b0;
        pc_new_o = 32'b0;
        if (exc_enter_o) begin
            pc_sel_o = 1'b1;
            pc_new_o = exc_target;
        end else if (mret_o) begin
            pc_sel_o = 1'b1;
            pc_new_o = ret_pc_i;
        end else if (ctrl_i.jump) begin
            pc_sel_o = 1'b1;
            pc_new_o = branch_target;
        end else if (ctrl_i.jalr) begin
            pc_sel_o = 1'b1;
            pc_new_o = jalr_target;
        end else if (branch_taken) begin
            pc_sel_o = 1'b1;
            pc_new_o = branch_target;
        end
    end

    assign flush_o = pc_sel_o;   // 任何重定向都冲刷两条在流指令

    //==========================================================================
    // 8. 写回数据与写回使能
    //==========================================================================
    always_comb begin
        if (ctrl_i.lui)
            ex_wdata_o = imm_i;
        else if (ctrl_i.mem_read)
            ex_wdata_o = load_data;
        else if (ctrl_i.jump || ctrl_i.jalr)
            ex_wdata_o = pc_i + 32'd4;
        else if (ctrl_i.csr_op != CSR_NONE)
            ex_wdata_o = csr_rdata_i;
        else if (ctrl_i.mul_en)
            ex_wdata_o = mul_y;
        else if (ctrl_i.div_en)
            ex_wdata_o = div_y;
        else
            ex_wdata_o = alu_y;
    end

    // 同步异常指令不提交、不写回；中断时当前指令正常提交
    assign ex_wreg_o     = valid_i && ctrl_i.reg_write && !sync_exc;
    assign ex_rd_o       = rd_i;
    assign ex_mem_read_o = valid_i && ctrl_i.mem_read;

    // 数据存储器访问使能（异常时屏蔽）
    assign dmem_en_o     = valid_i && (ctrl_i.mem_read || ctrl_i.mem_write) && !sync_exc;

    // 指令提交：有效且无同步异常（中断响应周期当前指令仍算提交）
    assign instr_ret_o   = valid_i && !sync_exc;

endmodule
