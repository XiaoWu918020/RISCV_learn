//==============================================================================
// File        : riscv_types.svh
// Description : 跨模块共享的打包数据类型定义。
//               采用 include guard，可被多个模块安全 `include；类型定义位于
//               编译单元全局作用域，因此可直接用于模块端口（兼容不支持
//               package typedef 端口的仿真器，如 Icarus Verilog 11）。
//==============================================================================
`ifndef RISCV_TYPES_SVH
`define RISCV_TYPES_SVH

// 译码控制总线（ID -> EX 之间传递的打包控制字段）
typedef struct packed {
    logic [4:0]  alu_op;       // ALU 操作编码
    logic [2:0]  imm_sel;      // 立即数类型
    logic        alu_src;      // ALU 第二操作数：0=rs2，1=imm
    logic        lui;          // lui 标志
    logic        auipc;        // auipc 标志
    logic        branch;       // 条件分支标志
    logic        jump;         // jal 标志
    logic        jalr;         // jalr 标志
    logic        mem_read;     // 加载使能
    logic        mem_write;    // 存储使能
    logic [1:0]  mem_size;     // 访存宽度：byte/half/word
    logic        mem_unsigned; // 加载零扩展标志（lbu/lhu）
    logic        reg_write;    // GPR 写回使能
    logic        mul_en;       // M 扩展：乘法
    logic        div_en;       // M 扩展：除法
    logic [2:0]  funct3;       // 分支/访存/M 扩展子操作编码
    logic [1:0]  csr_op;       // CSR 操作类型
    logic        csr_imm;      // CSR 立即数版本标志
    logic [11:0] csr_addr;     // CSR 地址
    logic        mret;         // mret 指令
    logic        ecall;        // ecall 指令
    logic        ebreak;       // ebreak 指令
    logic        illegal;      // 非法指令标志
    logic        rs1_used;     // rs1 是否被实际使用（冒险检测用）
    logic        rs2_used;     // rs2 是否被实际使用（冒险检测用）
} ctrl_bus_t;

`endif // RISCV_TYPES_SVH
