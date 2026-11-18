/*==============================================================================
 * diag2_main.c —— UART 读/写路径决定性诊断（不依赖中断 / FreeRTOS）
 * LED 分阶段长保持（每段约 1.5s），同时观察串口：
 *   阶段1 GPO=0x1  进入 main
 *   阶段2 盲发字符 'A'（不轮询 tx_ready），GPO=0x2
 *   阶段3 读 UART，GPO=0x3 表示读到 bit0=1，GPO=0x1 表示读到 0
 *   阶段4 盲发 'B'，随后慢闪
 * 串口收到 A/B 即证明写/发送路径正常；阶段3 直接给出读路径结果。
 *============================================================================*/
#include <stdint.h>

#define UART_REG  ( *( volatile uint32_t * ) 0x10000000UL )
#define GPO_REG   ( *( volatile uint32_t * ) 0x10001000UL )

static void hold( uint32_t n )
{
    for( volatile uint32_t i = 0; i < n; i++ ) { }
}

int main( void )
{
    /* 阶段1：进入 main */
    GPO_REG = 0x1U;
    hold( 6000000UL );

    /* 阶段2：盲发 'A'（不读 tx_ready），hold 远大于一帧时间 */
    UART_REG = 0x41U;
    hold( 200000UL );
    GPO_REG = 0x2U;
    hold( 6000000UL );

    /* 阶段3：读 UART，显示 bit0 */
    uint32_t v = UART_REG;
    GPO_REG = ( v & 1U ) ? 0x3U : 0x1U;
    hold( 6000000UL );

    /* 阶段4：盲发 'B'，随后慢闪 */
    UART_REG = 0x42U;
    hold( 200000UL );
    GPO_REG = 0x3U;
    for( ; ; )
    {
        GPO_REG ^= 0x3U;
        hold( 2000000UL );
    }
}
