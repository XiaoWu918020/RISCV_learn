#!/usr/bin/env python3
#==============================================================================
# File        : elf2hex.py
# Description : 直接解析 ELF32-LE，按程序头（PT_LOAD）的物理地址 p_paddr（LMA）
#               提取 IMEM 加载镜像，生成 $readmemh 用的扁平 32 位小端 hex。
#               跳过 LMA 落在 DMEM 的段（如 .probe），从而避免 objcopy -O binary
#               按 VMA 填充高地址导致的巨型镜像。
# Usage       : python elf2hex.py <in.elf> <out.hex> <imem_bytes>
#==============================================================================
import sys

PT_LOAD = 1


def read_elf32_le( path ):
    """解析 ELF32 小端，返回 [(lma, bytes), ...] 的可加载段列表。"""
    with open( path, "rb" ) as f:
        data = f.read()

    # ELF 标识：0x7f ELF；EI_CLASS=1(32bit)，EI_DATA=1(小端)
    assert data[:4] == b"\x7fELF", "不是 ELF 文件"
    assert data[4] == 1, "仅支持 ELF32"
    assert data[5] == 1, "仅支持小端"

    e_phoff = int.from_bytes( data[0x1C:0x20], "little" )
    e_phentsize = int.from_bytes( data[0x2A:0x2C], "little" )
    e_phnum = int.from_bytes( data[0x2C:0x2E], "little" )

    chunks = []
    for i in range( e_phnum ):
        base = e_phoff + i * e_phentsize
        p_type = int.from_bytes( data[base:base + 4], "little" )
        p_offset = int.from_bytes( data[base + 4:base + 8], "little" )
        p_paddr = int.from_bytes( data[base + 12:base + 16], "little" )
        p_filesz = int.from_bytes( data[base + 16:base + 20], "little" )

        if p_type == PT_LOAD and p_filesz > 0:
            chunks.append( ( p_paddr, data[p_offset:p_offset + p_filesz] ) )
    return chunks


def main():
    elf_path = sys.argv[1]
    hex_path = sys.argv[2]
    imem_bytes = int( sys.argv[3] )

    chunks = read_elf32_le( elf_path )
    img = bytearray( imem_bytes )
    end = 0

    for lma, blob in chunks:
        if lma >= imem_bytes:
            # LMA 在 DMEM 的段（.probe 等），不进 IMEM
            continue
        if lma + len( blob ) > imem_bytes:
            sys.exit( "ROM 镜像超过 IMEM 容量 %d 字节" % imem_bytes )
        img[lma:lma + len( blob )] = blob
        end = max( end, lma + len( blob ) )

    # 实际长度向上取整到 4 字节
    use = ( ( end + 3 ) // 4 ) * 4
    lines = []
    for i in range( 0, use, 4 ):
        word = ( img[i] |
                 ( img[i + 1] << 8 ) |
                 ( img[i + 2] << 16 ) |
                 ( img[i + 3] << 24 ) )
        lines.append( "%08x" % word )

    with open( hex_path, "w", encoding="ascii", newline="\n" ) as f:
        f.write( "\n".join( lines ) + "\n" )

    print( "hex: %d 个 32 位字，%d 字节 -> %s" % ( len(lines), use, hex_path ) )


if __name__ == "__main__":
    main()
