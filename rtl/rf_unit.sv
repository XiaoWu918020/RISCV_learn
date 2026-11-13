//==============================================================================
// File        : rf_unit.sv
// Module      : rf_unit —— 寄存器单元（RF）
// Description : 对应框图 RF_UNIT，内部包含：
//                 (1) gpr ：32×32 通用寄存器堆（x0 恒为 0，双读单写）
//                 (2) csr ：M 模式基础控制状态寄存器文件
//               CSR 实现机器模式运行、中断使能/挂起、异常现场保存与 mret
//               恢复所需的最小集合，并提供 mcycle/minstret 计数器。
//==============================================================================
module rf_unit (
    input  logic        clk,
    input  logic        rst_n,

    //----------------------------- GPR 读口 ----------------------------------
    input  logic [4:0]  rs1_addr_i,
    input  logic [4:0]  rs2_addr_i,
    output logic [31:0] rs1_data_o,
    output logic [31:0] rs2_data_o,

    //----------------------------- GPR 写口 ----------------------------------
    input  logic [4:0]  rd_addr_i,
    input  logic [31:0] rd_data_i,
    input  logic        rd_we_i,

    //----------------------------- CSR 访问 -----------------------------------
    input  logic [11:0] csr_addr_i,      // 当前 EX 指令访问的 CSR 地址
    input  logic [1:0]  csr_op_i,        // CSR_NONE/RW/RS/RC
    input  logic [31:0] csr_wdata_i,     // 已由执行级准备好的写数据
    output logic [31:0] csr_rdata_o,     // CSR 读出数据（写回 rd）
    output logic        csr_we_o,        // 当前 EX 指令是否真正写 CSR（冒险用）

    //----------------------------- 异常/中断 ----------------------------------
    input  logic        exc_enter_i,     // 异常/中断进入脉冲
    input  logic [31:0] exc_cause_i,     // mcause
    input  logic [31:0] exc_tval_i,      // mtval
    input  logic [31:0] exc_epc_i,       // 异常时保存的 PC
    input  logic        mret_i,          // mret 恢复脉冲
    output logic [31:0] ret_pc_o,        // mret 返回地址（mepc）

    input  logic [31:0] mip_i,           // 来自 CLINT 的挂起位图
    output logic        irq_req_o,       // 全局可屏蔽中断请求
    output logic [31:0] irq_cause_o,     // 最高优先级中断原因码

    output logic [31:0] mtvec_o,         // 异常入口向量（供执行级取目标地址）

    input  logic        instr_ret_i      // 指令提交脉冲（minstret 计数）
);

    import riscv_defines::*;

    //==========================================================================
    // (1) 通用寄存器堆 GPR
    //==========================================================================
    logic [31:0] gpr [REG_NUM];

    // 同步写
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < REG_NUM; i++) gpr[i] <= 32'b0;
        end else if (rd_we_i && (rd_addr_i != 5'd0)) begin
            gpr[rd_addr_i] <= rd_data_i;   // x0 写使能被屏蔽，恒为 0
        end
    end

    // 组合读（x0 直接返回 0）
    assign rs1_data_o = (rs1_addr_i == 5'd0) ? 32'b0 : gpr[rs1_addr_i];
    assign rs2_data_o = (rs2_addr_i == 5'd0) ? 32'b0 : gpr[rs2_addr_i];

    //==========================================================================
    // (2) 控制状态寄存器 CSR
    //==========================================================================
    // 实际寄存器存储
    logic        mstatus_mie;
    logic        mstatus_mpie;
    logic [31:0] mie_r;
    logic [31:0] mtvec_r;
    logic [31:0] mscratch_r;
    logic [31:0] mepc_r;
    logic [31:0] mcause_r;
    logic [31:0] mtval_r;
    logic [63:0] mcycle_r;
    logic [63:0] minstret_r;

    // misa：RV32 I/M（MXL=1，I=bit8，M=bit12）
    localparam logic [31:0] MISA_VAL = 32'h4000_1100;

    //--------------------------------------------------------------------------
    // CSR 组合读
    //--------------------------------------------------------------------------
    logic [31:0] mstatus_val, mie_val, mip_val;

    assign mstatus_val = {24'b0, mstatus_mpie, 3'b0, mstatus_mie, 3'b0};
    assign mie_val     = mie_r & (32'b1 << M_INT_ME | 32'b1 << M_INT_MT | 32'b1 << M_INT_MS);
    assign mip_val     = mip_i & (32'b1 << M_INT_ME | 32'b1 << M_INT_MT | 32'b1 << M_INT_MS);

    always_comb begin
        unique case (csr_addr_i)
            CSR_MVENDORID: csr_rdata_o = 32'b0;
            CSR_MARCHID:   csr_rdata_o = 32'b0;
            CSR_MIMPID:    csr_rdata_o = 32'b0;
            CSR_MHARTID:   csr_rdata_o = 32'b0;
            CSR_MISA:      csr_rdata_o = MISA_VAL;
            CSR_MSTATUS:   csr_rdata_o = mstatus_val;
            CSR_MIE:       csr_rdata_o = mie_val;
            CSR_MTVEC:     csr_rdata_o = mtvec_r;
            CSR_MSCRATCH:  csr_rdata_o = mscratch_r;
            CSR_MEPC:      csr_rdata_o = mepc_r;
            CSR_MCAUSE:    csr_rdata_o = mcause_r;
            CSR_MTVAL:     csr_rdata_o = mtval_r;
            CSR_MIP:       csr_rdata_o = mip_val;
            CSR_MCYCLE,
            CSR_CYCLE:     csr_rdata_o = mcycle_r[31:0];
            CSR_MINSTRET,
            CSR_INSTRET:   csr_rdata_o = minstret_r[31:0];
            default:       csr_rdata_o = 32'b0;
        endcase
    end

    //--------------------------------------------------------------------------
    // CSR 写使能与写数据
    //   RW 无条件写；RS/RC 仅在写数据非 0 时写（符合特权规范）
    //--------------------------------------------------------------------------
    logic csr_wen;
    assign csr_wen  = (csr_op_i != CSR_NONE) &&
                      ((csr_op_i == CSR_RW) || (csr_wdata_i != 32'b0));
    assign csr_we_o = csr_wen;

    logic [31:0] csr_wnew;   // 写后新值
    always_comb begin
        unique case (csr_op_i)
            CSR_RW:   csr_wnew = csr_wdata_i;
            CSR_RS:   csr_wnew = csr_rdata_o | csr_wdata_i;
            CSR_RC:   csr_wnew = csr_rdata_o & ~csr_wdata_i;
            default:  csr_wnew = csr_rdata_o;
        endcase
    end

    //--------------------------------------------------------------------------
    // CSR 寄存器更新（含异常进入、mret 恢复、计数器）
    //--------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_mie  <= 1'b0;
            mstatus_mpie <= 1'b1;
            mie_r        <= 32'b0;
            mtvec_r      <= 32'b0;
            mscratch_r   <= 32'b0;
            mepc_r       <= 32'b0;
            mcause_r     <= 32'b0;
            mtval_r      <= 32'b0;
            mcycle_r     <= 64'b0;
            minstret_r   <= 64'b0;
        end else begin
            // 计数器：mcycle 每周期自增，minstret 按提交自增
            mcycle_r   <= mcycle_r + 64'd1;
            if (instr_ret_i) minstret_r <= minstret_r + 64'd1;

            if (exc_enter_i) begin
                // 进入异常/中断：关全局中断并保存现场
                mstatus_mpie <= mstatus_mie;
                mstatus_mie  <= 1'b0;
                mepc_r       <= exc_epc_i;
                mcause_r     <= exc_cause_i;
                mtval_r      <= exc_tval_i;
            end else if (mret_i) begin
                // mret：恢复全局中断
                mstatus_mie  <= mstatus_mpie;
                mstatus_mpie <= 1'b1;
            end else if (csr_wen) begin
                // 普通 CSR 写（白名单内才生效）
                unique case (csr_addr_i)
                    CSR_MSTATUS: begin
                        mstatus_mie  <= csr_wnew[M_STATUS_MIE];
                        mstatus_mpie <= csr_wnew[M_STATUS_MPIE];
                    end
                    CSR_MIE:      mie_r       <= csr_wnew;
                    CSR_MTVEC:    mtvec_r     <= csr_wnew;
                    CSR_MSCRATCH: mscratch_r  <= csr_wnew;
                    CSR_MEPC:     mepc_r      <= csr_wnew;
                    CSR_MCAUSE:   mcause_r    <= csr_wnew;
                    CSR_MTVAL:    mtval_r     <= csr_wnew;
                    default: ; // 只读/未实现寄存器：忽略写
                endcase
            end
        end
    end

    // mret 返回地址
    assign ret_pc_o = mepc_r;

    // 异常入口向量输出
    assign mtvec_o  = mtvec_r;

    //--------------------------------------------------------------------------
    // 全局中断请求：mstatus.MIE=1 且（mie & mip）存在有效挂起
    // 优先级（实现定义）：外部中断 > 定时器中断 > 软件中断
    //--------------------------------------------------------------------------
    logic [31:0] pending;
    assign pending = mie_val & mip_val;

    always_comb begin
        if (pending[M_INT_ME]) begin
            irq_req_o   = mstatus_mie;
            irq_cause_o = CAUSE_E_INT;
        end else if (pending[M_INT_MT]) begin
            irq_req_o   = mstatus_mie;
            irq_cause_o = CAUSE_T_INT;
        end else if (pending[M_INT_MS]) begin
            irq_req_o   = mstatus_mie;
            irq_cause_o = CAUSE_S_INT;
        end else begin
            irq_req_o   = 1'b0;
            irq_cause_o = 32'b0;
        end
    end

endmodule
