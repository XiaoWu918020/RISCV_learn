/*==============================================================================
 * File        : main.c
 * Description : FreeRTOS 多任务调度演示。本 SoC 无 UART，改用固定 DMEM 探测
 *               段 .probe 中的计数器体现任务运行与上下文切换，testbench 直接
 *               按 dmem_mem 字索引观测：
 *                 [0] 任务1 计数   [1] 任务2 计数
 *                 [2] 存活计数     [3] 错误标志
 *               两个任务以不同周期、不同优先级运行，验证抢占与切换。
 *============================================================================*/
#include "FreeRTOS.h"
#include "task.h"

/* RISC-V 端口提供的统一 trap 入口（需由应用写入 mtvec） */
extern void freertos_risc_v_trap_handler( void );

/* 观测变量：固定落在 DMEM 最前的 .probe 段（对应 dmem_mem[0..3]） */
__attribute__( ( section( ".probe" ) ) )
volatile uint32_t g_probe[4];

#define PROBE_TASK1_COUNT   g_probe[0]
#define PROBE_TASK2_COUNT   g_probe[1]
#define PROBE_ALIVE         g_probe[2]
#define PROBE_ERROR         g_probe[3]

/*------------------------------------------------------------------------------
 * 任务1：每 1 个 tick 递增一次（优先级 2）
 *----------------------------------------------------------------------------*/
static void vTask1( void * pvParameters )
{
    ( void ) pvParameters;
    for( ; ; )
    {
        PROBE_TASK1_COUNT++;
        PROBE_ALIVE++;
        vTaskDelay( pdMS_TO_TICKS( 1 ) );
    }
}

/*------------------------------------------------------------------------------
 * 任务2：每 2 个 tick 递增一次（优先级 1），周期不同以区分两个任务
 *----------------------------------------------------------------------------*/
static void vTask2( void * pvParameters )
{
    ( void ) pvParameters;
    for( ; ; )
    {
        PROBE_TASK2_COUNT++;
        vTaskDelay( pdMS_TO_TICKS( 2 ) );
    }
}

/*------------------------------------------------------------------------------
 * 主程序：安装 trap、创建任务、启动调度器
 *----------------------------------------------------------------------------*/
int main( void )
{
    /* 1. 安装统一 trap 入口（RISC-V 端口不自动设置 mtvec） */
    __asm volatile ( "csrw mtvec, %0" : : "r" ( freertos_risc_v_trap_handler ) );

    /* 2. 清零探测变量 */
    for( int i = 0; i < 4; i++ )
    {
        g_probe[i] = 0;
    }

    /* 3. 创建两个任务（不同优先级，体现抢占调度） */
    xTaskCreate( vTask1, "task1", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vTask2, "task2", configMINIMAL_STACK_SIZE, NULL, 1, NULL );

    /* 4. 启动调度器，正常情况下不返回 */
    vTaskStartScheduler();

    /* 仅当堆不足导致调度器启动失败时才会走到这里 */
    PROBE_ERROR = 1;
    for( ; ; )
    {
    }
}

/*------------------------------------------------------------------------------
 * 错误钩子：置错误标志后停住
 *----------------------------------------------------------------------------*/
void vApplicationMallocFailedHook( void )
{
    PROBE_ERROR = 1;
    for( ; ; )
    {
    }
}

void vApplicationStackOverflowHook( TaskHandle_t xTask, char * pcTaskName )
{
    ( void ) xTask;
    ( void ) pcTaskName;
    PROBE_ERROR = 1;
    for( ; ; )
    {
    }
}
