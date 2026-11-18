/*==============================================================================
 * File        : main.c
 * Description : FreeRTOS 多任务演示。同时支持两种观测：
 *                 (1) 仿真：固定 DMEM 探测段 .probe（g_probe），testbench 按
 *                     dmem_mem 字索引观测：[0]cnt1 [1]cnt2 [2]alive [3]err
 *                 (2) 上板：内存映射 UART 轮询打印任务计数，GPO 寄存器驱动 LED
 *               两个任务以不同周期、不同优先级运行，验证抢占与上下文切换。
 *
 *   外设地址（与 riscv_soc_fpga.sv 一致）：
 *     UART 0x1000_0000：offset0 写=发送字符，读 bit0=发送器空闲
 *     GPO  0x1000_1000：32 位输出寄存器，bit0/bit1 接板级 LED
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
 * 板级外设寄存器访问
 *----------------------------------------------------------------------------*/
#define UART_BASE_ADDR      0x10000000UL
#define GPO_BASE_ADDR       0x10001000UL
#define REG32( addr )       ( *( volatile uint32_t * ) ( addr ) )
#define UART_STATUS_REG     REG32( UART_BASE_ADDR )       /* bit0=tx_ready */
#define UART_TDR_REG        REG32( UART_BASE_ADDR )       /* 写=发送字符 */
#define GPO_REG             REG32( GPO_BASE_ADDR )

/*------------------------------------------------------------------------------
 * UART 轮询驱动（不依赖 printf，裸机最小实现）
 *----------------------------------------------------------------------------*/

/* 发送一个字符：等待发送器空闲再写入 */
static void uart_putc( char c )
{
    while( ( UART_STATUS_REG & 1U ) == 0U )
    {
    }
    UART_TDR_REG = ( uint32_t ) ( uint8_t ) c;
}

/* 发送字符串 */
static void uart_puts( const char * s )
{
    while( *s != '\0' )
    {
        uart_putc( *s );
        s++;
    }
}

/* 发送无符号十进制数 */
static void uart_print_dec( uint32_t v )
{
    char buf[11];
    int  i = 0;

    if( v == 0U )
    {
        uart_putc( '0' );
        return;
    }
    while( v != 0U )
    {
        buf[i++] = ( char ) ( '0' + ( v % 10U ) );
        v /= 10U;
    }
    while( i > 0 )
    {
        uart_putc( buf[--i] );
    }
}

/* 原子打印一整行任务日志：防止另一个任务在 tx_ready 检查与写 TDR 之间抢占。
 * 整条日志期间仅关闭 CPU 中断，UART 与 mtime 硬件仍继续运行。 */
static void uart_print_count( const char * tag, uint32_t value )
{
    taskENTER_CRITICAL();
    uart_puts( tag );
    uart_print_dec( value );
    uart_puts( "\r\n" );
    taskEXIT_CRITICAL();
}

/* 同步 LED：bit0=cnt1 心跳，bit1=cnt2 心跳（两任务共用，整体重写避免互相覆盖） */
static void led_refresh( void )
{
    uint32_t g = ( PROBE_TASK1_COUNT & 1U ) |
                 ( ( PROBE_TASK2_COUNT & 1U ) << 1 );
    GPO_REG = g;
}

/*------------------------------------------------------------------------------
 * 任务1：每 1 个 tick 递增一次（优先级 2），每 10 次打印一次
 *----------------------------------------------------------------------------*/
static void vTask1( void * pvParameters )
{
    ( void ) pvParameters;
    for( ; ; )
    {
        PROBE_TASK1_COUNT++;
        PROBE_ALIVE++;
        led_refresh();

        if( ( PROBE_TASK1_COUNT % 10U ) == 0U )
        {
            uart_print_count( "[task1] count=", PROBE_TASK1_COUNT );
        }

        vTaskDelay( pdMS_TO_TICKS( 1 ) );
    }
}

/*------------------------------------------------------------------------------
 * 任务2：每 2 个 tick 递增一次（优先级 1），每 5 次打印一次
 *----------------------------------------------------------------------------*/
static void vTask2( void * pvParameters )
{
    ( void ) pvParameters;
    for( ; ; )
    {
        PROBE_TASK2_COUNT++;
        led_refresh();

        if( ( PROBE_TASK2_COUNT % 5U ) == 0U )
        {
            uart_print_count( "[task2] count=", PROBE_TASK2_COUNT );
        }

        vTaskDelay( pdMS_TO_TICKS( 2 ) );
    }
}

/*------------------------------------------------------------------------------
 * 主程序：安装 trap、清零观测、创建任务、启动调度器
 *----------------------------------------------------------------------------*/
int main( void )
{
    /* 1. 安装统一 trap 入口（RISC-V 端口不自动设置 mtvec） */
    __asm volatile ( "csrw mtvec, %0" : : "r" ( freertos_risc_v_trap_handler ) );

    /* 2. 清零探测变量与 LED */
    for( int i = 0; i < 4; i++ )
    {
        g_probe[i] = 0;
    }
    GPO_REG = 0U;

    /* 3. 上电提示 */
    uart_puts( "\r\n==== FreeRTOS on RV32IM (3-stage) start ====\r\n" );

    /* 4. 创建两个任务（不同优先级，体现抢占调度） */
    xTaskCreate( vTask1, "task1", configMINIMAL_STACK_SIZE, NULL, 2, NULL );
    xTaskCreate( vTask2, "task2", configMINIMAL_STACK_SIZE, NULL, 1, NULL );

    /* 5. 启动调度器，正常情况下不返回 */
    vTaskStartScheduler();

    /* 仅当堆不足导致调度器启动失败时才会走到这里 */
    PROBE_ERROR = 1;
    uart_puts( "ERROR: scheduler start failed\r\n" );
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
    uart_puts( "ERROR: malloc failed\r\n" );
    for( ; ; )
    {
    }
}

void vApplicationStackOverflowHook( TaskHandle_t xTask, char * pcTaskName )
{
    ( void ) xTask;
    ( void ) pcTaskName;
    PROBE_ERROR = 1;
    uart_puts( "ERROR: stack overflow\r\n" );
    for( ; ; )
    {
    }
}
