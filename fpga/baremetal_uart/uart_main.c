/*==============================================================================
 * uart_main.c —— 裸机 UART 递进验证（不依赖中断 / CSR / FreeRTOS）
 * 用 GPO（LED）编码执行阶段，肉眼即可判断卡在哪一步：
 *   阶段1  GPO=0x1  进入 main
 *   阶段2  GPO=0x2  从 UART 地址成功读到 tx_ready=1（读不到则 GPO=0）
 *   阶段3  实际 uart_puts 发送字符串
 *   阶段4  GPO=0x3  发送完成，随后慢闪
 * 同时串口应收到 "HELLO UART 123"。
 *============================================================================*/
#include <stdint.h>

#define UART_BASE_ADDR  0x10000000UL
#define GPO_BASE_ADDR   0x10001000UL
#define UART_REG        ( *( volatile uint32_t * ) UART_BASE_ADDR )
#define GPO_REG         ( *( volatile uint32_t * ) GPO_BASE_ADDR )

static void delay( uint32_t n )
{
    for( volatile uint32_t i = 0; i < n; i++ ) { }
}

static void uart_putc( char c )
{
    while( ( UART_REG & 1U ) == 0U ) { }   /* 轮询 tx_ready */
    UART_REG = ( uint32_t ) ( uint8_t ) c;
}

static void uart_puts( const char * s )
{
    while( *s != '\0' ) { uart_putc( *s++ ); }
}

int main( void )
{
    /* 阶段1：进入 main */
    GPO_REG = 0x1U;
    delay( 400000UL );

    /* 阶段2：从 UART 地址读 tx_ready，读到 1 才点亮 LED2 */
    uint32_t rdy = UART_REG & 1U;
    GPO_REG = rdy ? 0x2U : 0x0U;
    delay( 400000UL );

    /* 阶段3：实际发送 */
    uart_puts( "HELLO UART 123\r\n" );

    /* 阶段4：发送完成，两灯亮，随后慢闪 */
    GPO_REG = 0x3U;
    for( ; ; )
    {
        GPO_REG ^= 0x3U;
        delay( 1000000UL );
    }
}
