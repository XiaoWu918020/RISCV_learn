/*==============================================================================
 * File        : FreeRTOSConfig.h
 * Description : FreeRTOS 内核配置（针对本三级流水线 RV32IM 核 + 标准 SiFive
 *               CLINT）。RISC-V 端口通过本文件获取 mtime/mtimecmp 地址、CPU
 *               时钟、tick 周期、栈与堆尺寸等；本配置为精简版，仅启用
 *               多任务调度演示所需功能，以控制 IMEM 内代码体积。
 *============================================================================*/
#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

/*------------------------------------------------------------------------------
 * 1. 时钟与定时器（地址与 riscv_soc.sv / clint.sv 对齐）
 *    CLINT 基址 0x4000_0000：mtime 偏移 0xBFF8，mtimecmp 偏移 0x4000
 *----------------------------------------------------------------------------*/
#define configMTIME_BASE_ADDRESS        ( 0x40000000UL + 0xBFF8UL ) /* 0x4000BFF8 */
#define configMTIMECMP_BASE_ADDRESS     ( 0x40000000UL + 0x4000UL ) /* 0x40004000 */
#define configCPU_CLOCK_HZ              ( 25000000UL )              /* 25 MHz（MMCM 后实际系统时钟） */
#define configTICK_RATE_HZ              ( ( TickType_t ) 1000UL )    /* 1 ms/tick */

/*------------------------------------------------------------------------------
 * 2. 调度与任务
 *----------------------------------------------------------------------------*/
#define configUSE_PREEMPTION            1   /* 抢占式调度 */
#define configUSE_TIME_SLICING          1   /* 同优先级时间片轮转 */
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 1   /* 位图选最高优先级（优先级<=32） */
#define configMAX_PRIORITIES            ( 7U )
#define configMINIMAL_STACK_SIZE        ( ( uint16_t ) 128 )  /* 单位：字（4字节） */
#define configMAX_TASK_NAME_LEN         ( 16 )
#define configUSE_16_BIT_TICKS          0   /* 32 位 tick */
#define configIDLE_SHOULD_YIELD         1
#define configQUEUE_REGISTRY_SIZE       8
#define configENABLE_BACKWARD_COMPATIBILITY 1

/*------------------------------------------------------------------------------
 * 3. 内存分配（heap_4，支持静态+动态分配）
 *----------------------------------------------------------------------------*/
#define configSUPPORT_STATIC_ALLOCATION  0
#define configSUPPORT_DYNAMIC_ALLOCATION 1
#define configTOTAL_HEAP_SIZE           ( ( size_t ) 8192 )  /* 8 KB */

/* 独立 ISR 栈：静态分配，避免依赖链接脚本的 __freertos_irq_stack_top */
#define configISR_STACK_SIZE_WORDS      ( 256 )

/*------------------------------------------------------------------------------
 * 4. 同步原语与可选组件（演示精简：关闭软件定时器/队列集/互斥量）
 *----------------------------------------------------------------------------*/
#define configUSE_MUTEXES               0
#define configUSE_RECURSIVE_MUTEXES     0
#define configUSE_COUNTING_SEMAPHORES   0
#define configUSE_QUEUE_SETS            0
#define configUSE_TIMERS                0
#define configUSE_TASK_NOTIFICATIONS    1

/*------------------------------------------------------------------------------
 * 5. 调试与钩子
 *----------------------------------------------------------------------------*/
#define configCHECK_FOR_STACK_OVERFLOW  2   /* 栈溢出检测（方法2） */
#define configUSE_MALLOC_FAILED_HOOK    1
#define configUSE_IDLE_HOOK             0
#define configUSE_TICK_HOOK             0
#define configUSE_TRACE_FACILITY        1

/* 断言：条件不成立时关中断并停住，便于仿真定位 */
#define configASSERT( x ) \
    if( ( x ) == 0 ) { taskDISABLE_INTERRUPTS(); for( ; ; ) {} }

/*------------------------------------------------------------------------------
 * 6. 可选 API 函数裁剪（FreeRTOS V10+ 风格）
 *----------------------------------------------------------------------------*/
#define INCLUDE_vTaskPrioritySet        1
#define INCLUDE_uxTaskPriorityGet       1
#define INCLUDE_vTaskDelete             1
#define INCLUDE_vTaskCleanUpResources   0
#define INCLUDE_vTaskSuspend            1
#define INCLUDE_vTaskDelayUntil         1
#define INCLUDE_vTaskDelay              1
#define INCLUDE_xTaskGetSchedulerState  1
#define INCLUDE_xTimerPendFunctionCall  0
#define INCLUDE_uxTaskGetStackHighWaterMark 1

#endif /* FREERTOS_CONFIG_H */
