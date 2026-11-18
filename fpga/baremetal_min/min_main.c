/*==============================================================================
 * File        : min_main.c
 * Description : 最小硬件 Bring-up 验证（不依赖中断 / UART / FreeRTOS）。
 *               仅通过最基本的取指、运算、sw 写 GPO，让两个 LED 同步慢闪，
 *               用于二分定位“正式 FreeRTOS 固件全灭”：
 *                 - 本固件能闪 -> CPU 取指/执行/写 GPO 基本通路正常，问题在
 *                   FreeRTOS 的中断/trap 环节
 *                 - 本固件不闪 -> 最底层取指或综合/存储就有问题
 *               GPO 0x1000_1000：bit0->LED1 bit1->LED2，写 0x3 同时点亮。
 *============================================================================*/
#include <stdint.h>

#define GPO_BASE_ADDR  0x10001000UL
#define GPO_REG        ( *( volatile uint32_t * ) GPO_BASE_ADDR )

int main( void )
{
    uint32_t g = 0x3UL;   /* 初始两个 LED 都点亮 */

    for( ; ; )
    {
        GPO_REG = g;                 /* 写 GPO 驱动 LED */
        g = g ^ 0x3UL;              /* bit0/bit1 同时翻转 */

        /* 纯软件忙等：约 100 万次循环，25MHz 下约 0.2~0.3s，肉眼可见慢闪 */
        for( volatile uint32_t i = 0; i < 1000000UL; i++ )
        {
        }
    }
}
