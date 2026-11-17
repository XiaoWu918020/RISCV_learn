/*==============================================================================
 * File        : support.c
 * Description : 裸机最小运行库支持。-nostdlib 不链接标准库与 libgcc，本文件
 *               提供内核与端口会用到的内存函数，以及编译器辅助函数
 *               __clzsi2（前导零计数，本核无 zbb 扩展，软件实现）。
 * Note        : freestanding 环境下 stdint.h/stddef.h 等编译器自带头仍可用。
 *============================================================================*/
#include <stdint.h>
#include <stddef.h>

/*------------------------------------------------------------------------------
 * memset：把 dst 起 n 字节填为 c
 *----------------------------------------------------------------------------*/
void * memset( void * dst, int c, size_t n )
{
    unsigned char * p = ( unsigned char * ) dst;
    while( n-- )
    {
        *p++ = ( unsigned char ) c;
    }
    return dst;
}

/*------------------------------------------------------------------------------
 * memcpy：从 src 拷贝 n 字节到 dst（两区域不重叠）
 *----------------------------------------------------------------------------*/
void * memcpy( void * dst, const void * src, size_t n )
{
    unsigned char * d = ( unsigned char * ) dst;
    const unsigned char * s = ( const unsigned char * ) src;
    while( n-- )
    {
        *d++ = *s++;
    }
    return dst;
}

/*------------------------------------------------------------------------------
 * memmove：可处理重叠区域的拷贝
 *----------------------------------------------------------------------------*/
void * memmove( void * dst, const void * src, size_t n )
{
    unsigned char * d = ( unsigned char * ) dst;
    const unsigned char * s = ( const unsigned char * ) src;

    if( d < s )
    {
        while( n-- )
        {
            *d++ = *s++;
        }
    }
    else
    {
        d += n;
        s += n;
        while( n-- )
        {
            *--d = *--s;
        }
    }
    return dst;
}

/*------------------------------------------------------------------------------
 * memcmp：比较两区域前 n 字节，返回首个差异的差值
 *----------------------------------------------------------------------------*/
int memcmp( const void * a, const void * b, size_t n )
{
    const unsigned char * x = ( const unsigned char * ) a;
    const unsigned char * y = ( const unsigned char * ) b;

    while( n-- )
    {
        if( *x != *y )
        {
            return ( int ) *x - ( int ) *y;
        }
        x++;
        y++;
    }
    return 0;
}

/*------------------------------------------------------------------------------
 * __clzsi2：对应 __builtin_clz，返回 32 位值的前导零个数；x=0 时返回 32
 *----------------------------------------------------------------------------*/
int __clzsi2( uint32_t x )
{
    int n = 0;

    if( x == 0U )
    {
        return 32;
    }
    if( ( x & 0xFFFF0000U ) == 0U )
    {
        n += 16;
        x <<= 16;
    }
    if( ( x & 0xFF000000U ) == 0U )
    {
        n += 8;
        x <<= 8;
    }
    if( ( x & 0xF0000000U ) == 0U )
    {
        n += 4;
        x <<= 4;
    }
    if( ( x & 0xC0000000U ) == 0U )
    {
        n += 2;
        x <<= 2;
    }
    if( ( x & 0x80000000U ) == 0U )
    {
        n += 1;
    }
    return n;
}
