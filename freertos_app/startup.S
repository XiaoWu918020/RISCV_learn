/*==============================================================================
 * File        : startup.S
 * Description : 复位启动入口（RV32，裸机）。复位后 PC 指向 IMEM 起始的 _start，
 *               依次完成：
 *                 1. 初始化栈指针 sp 与全局指针 gp（符号由 link.ld 导出）
 *                 2. 清零 .bss 段
 *                 3. 把 .data 从 IMEM 加载镜像（LMA）拷贝到 DMEM 运行地址（VMA）
 *                 4. 调用 main；main 正常情况下不会返回，若返回则进入死循环
 * Note        : 本文件与 FreeRTOS 端口的 portASM.S 均由 GNU 汇编器汇编，
 *               可直接使用 la/call 等伪指令。
 *============================================================================*/

    .section .text.init, "ax"
    .globl _start
    .type  _start, @function

_start:
    /* 1. 初始化栈与全局指针 */
    la      sp, _stack_top
    la      gp, __global_pointer$

    /* 2. 清零 .bss：t0 = 当前地址，t1 = 结束地址 */
    la      t0, _sbss
    la      t1, _ebss
bss_loop:
    bgeu    t0, t1, bss_done        /* 当前地址 >= 结束地址，清零完成 */
    sw      x0, 0(t0)
    addi    t0, t0, 4
    j       bss_loop
bss_done:

    /* 3. 拷贝 .data：t0 = 源 _sidata，t1 = 目的 _sdata，t2 = 结束 _edata */
    la      t0, _sidata
    la      t1, _sdata
    la      t2, _edata
data_loop:
    bgeu    t1, t2, data_done       /* 目的地址 >= 结束地址，拷贝完成 */
    lw      t3, 0(t0)
    sw      t3, 0(t1)
    addi    t0, t0, 4
    addi    t1, t1, 4
    j       data_loop
data_done:

    /* 4. 进入 C 主程序（此时全局中断默认关闭，由后续调度器统一管理） */
    call    main

    /* main 不应返回；若返回则在此停住，避免跑飞 */
hang:
    j       hang

    .size _start, . - _start
