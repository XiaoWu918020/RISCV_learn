//==============================================================================
// File        : riscv_core.sv
// Module      : riscv_core —— 三级流水线 RISC-V（RV32IM）核顶层
// Description : 按框图例化并互联五大单元：
//                 if_unit  一级取指（pc + if_id）
//                 id_unit  二级译码（id + id_ex，含转发/冒险）
//                 rf_unit  寄存器单元（gpr + csr）
//                 ex_unit  三级执行（cu + alu/mul/div）
//                 clint    本地中断器（mtime/mtimecmp/软/外部中断）
//               对外仅暴露指令/数据存储器接口、CLINT 总线口与外部中断，
//               存储器均按“组合读”模型对接（testbench 提供行为模型）。
//==============================================================================
`include "riscv_types.svh"
module riscv_core #(
    parameter logic [31:0] PC_RST = 32'h0000_0000
) (
    input  logic        clk,
    input  logic        rst_n,

    //------------------------- 指令存储器（组合读） --------------------------
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    //------------------------- 数据存储器 ------------------------------------
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    output logic [3:0]  dmem_wbe,
    output logic        dmem_en,
    input  logic [31:0] dmem_rdata,

    //------------------------- CLINT 总线 ------------------------------------
    input  logic [31:0] clint_addr,
    input  logic [31:0] clint_wdata,
    input  logic        clint_we,
    input  logic        clint_re,
    output logic [31:0] clint_rdata,

    input  logic        ext_irq        // 机器外部中断
);

    import riscv_defines::*;

    //--------------------------------------------------------------------------
    // 内部互联信号
    //--------------------------------------------------------------------------
    // IF/ID
    logic [31:0] ifid_pc;
    logic [31:0] ifid_inst;
    logic        ifid_valid;

    // 寄存器堆读口/写口
    logic [4:0]  rs1_addr, rs2_addr;
    logic [31:0] rs1_data, rs2_data;
    logic [4:0]  ex_rd;
    logic [31:0] ex_wdata;
    logic        ex_wreg, ex_mem_read;

    // ID/EX
    logic [31:0] idex_pc, idex_reg_a, idex_reg_b, idex_imm, idex_inst;
    logic        idex_valid;
    logic [4:0]  idex_rs1, idex_rs2, idex_rd;
    ctrl_bus_t   idex_ctrl;

    // 流水线控制
    logic        stall;
    logic        flush;
    logic        pc_sel;
    logic [31:0] pc_new;

    // CSR / 异常
    logic [11:0] csr_addr;
    logic [1:0]  csr_op;
    logic [31:0] csr_wdata, csr_rdata;
    logic        ex_csr_we;
    logic        exc_enter, mret;
    logic [31:0] exc_cause, exc_tval, exc_epc, ret_pc, mtvec;

    // 中断
    logic [31:0] mip;
    logic        irq_req;
    logic [31:0] irq_cause;
    logic        instr_ret;

    //==========================================================================
    // 一级：取指单元
    //==========================================================================
    if_unit #(
        .PC_RST (PC_RST)
    ) u_if (
        .clk          (clk),
        .rst_n        (rst_n),
        .stall_i      (stall),
        .flush_i      (flush),
        .pc_sel_i     (pc_sel),
        .pc_new_i     (pc_new),
        .imem_addr_o  (imem_addr),
        .imem_rdata_i (imem_rdata),
        .ifid_pc_o    (ifid_pc),
        .ifid_inst_o  (ifid_inst),
        .ifid_valid_o (ifid_valid)
    );

    //==========================================================================
    // 二级：译码单元
    //==========================================================================
    id_unit u_id (
        .clk            (clk),
        .rst_n          (rst_n),
        .ifid_pc_i      (ifid_pc),
        .ifid_inst_i    (ifid_inst),
        .ifid_valid_i   (ifid_valid),
        .flush_i        (flush),
        .gpr_a_i        (rs1_data),
        .gpr_b_i        (rs2_data),
        .ex_wreg_i      (ex_wreg),
        .ex_rd_i        (ex_rd),
        .ex_wdata_i     (ex_wdata),
        .ex_mem_read_i  (ex_mem_read),
        .ex_csr_we_i    (ex_csr_we),
        .ex_csr_addr_i  (csr_addr),
        .rs1_addr_o     (rs1_addr),
        .rs2_addr_o     (rs2_addr),
        .stall_o        (stall),
        .idex_pc_o      (idex_pc),
        .idex_valid_o   (idex_valid),
        .idex_ctrl_o    (idex_ctrl),
        .idex_rs1_o     (idex_rs1),
        .idex_rs2_o     (idex_rs2),
        .idex_rd_o      (idex_rd),
        .idex_reg_a_o   (idex_reg_a),
        .idex_reg_b_o   (idex_reg_b),
        .idex_imm_o     (idex_imm),
        .idex_inst_o    (idex_inst)
    );

    //==========================================================================
    // 寄存器单元：GPR + CSR
    //==========================================================================
    rf_unit u_rf (
        .clk          (clk),
        .rst_n        (rst_n),
        .rs1_addr_i   (rs1_addr),
        .rs2_addr_i   (rs2_addr),
        .rs1_data_o   (rs1_data),
        .rs2_data_o   (rs2_data),
        .rd_addr_i    (ex_rd),
        .rd_data_i    (ex_wdata),
        .rd_we_i      (ex_wreg),
        .csr_addr_i   (csr_addr),
        .csr_op_i     (csr_op),
        .csr_wdata_i  (csr_wdata),
        .csr_rdata_o  (csr_rdata),
        .csr_we_o     (),
        .exc_enter_i  (exc_enter),
        .exc_cause_i  (exc_cause),
        .exc_tval_i   (exc_tval),
        .exc_epc_i    (exc_epc),
        .mret_i       (mret),
        .ret_pc_o     (ret_pc),
        .mip_i        (mip),
        .irq_req_o    (irq_req),
        .irq_cause_o  (irq_cause),
        .mtvec_o      (mtvec),
        .instr_ret_i  (instr_ret)
    );

    //==========================================================================
    // 三级：执行单元
    //==========================================================================
    ex_unit u_ex (
        .pc_i          (idex_pc),
        .valid_i       (idex_valid),
        .ctrl_i        (idex_ctrl),
        .rs1_i         (idex_rs1),
        .rs2_i         (idex_rs2),
        .rd_i          (idex_rd),
        .reg_a_i       (idex_reg_a),
        .reg_b_i       (idex_reg_b),
        .imm_i         (idex_imm),
        .inst_i        (idex_inst),
        .id_pc_i       (ifid_pc),
        .id_valid_i    (ifid_valid),
        .dmem_addr_o   (dmem_addr),
        .dmem_wdata_o  (dmem_wdata),
        .dmem_wbe_o    (dmem_wbe),
        .dmem_en_o     (dmem_en),
        .dmem_rdata_i  (dmem_rdata),
        .ex_wreg_o     (ex_wreg),
        .ex_rd_o       (ex_rd),
        .ex_wdata_o    (ex_wdata),
        .ex_mem_read_o (ex_mem_read),
        .csr_addr_o    (csr_addr),
        .csr_op_o      (csr_op),
        .csr_wdata_o   (csr_wdata),
        .csr_rdata_i  (csr_rdata),
        .ex_csr_we_o   (ex_csr_we),
        .exc_enter_o   (exc_enter),
        .exc_cause_o   (exc_cause),
        .exc_tval_o    (exc_tval),
        .exc_epc_o     (exc_epc),
        .mret_o        (mret),
        .ret_pc_i      (ret_pc),
        .mtvec_i       (mtvec),
        .irq_req_i     (irq_req),
        .irq_cause_i   (irq_cause),
        .pc_sel_o      (pc_sel),
        .pc_new_o      (pc_new),
        .flush_o       (flush),
        .instr_ret_o   (instr_ret)
    );

    //==========================================================================
    // 本地中断器
    //==========================================================================
    clint u_clint (
        .clk       (clk),
        .rst_n     (rst_n),
        .addr_i    (clint_addr),
        .wdata_i   (clint_wdata),
        .we_i      (clint_we),
        .re_i      (clint_re),
        .rdata_o   (clint_rdata),
        .ext_irq_i (ext_irq),
        .mip_o     (mip)
    );

endmodule
