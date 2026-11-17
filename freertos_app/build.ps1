#==============================================================================
# File        : build.ps1
# Description : FreeRTOS 固件一键构建脚本（Windows + xPack 工具链）。
#               依次完成：编译内核/端口/堆/应用 -> 链接 -> 生成 bin -> 转换为
#               SoC 仿真用扁平 hex（build\firmware.hex）。
# Note        : 本核 RV32IM，固定 -march=rv32im -mabi=ilp32；裸机采用
#               -ffreestanding -nostdlib，不依赖标准库启动文件。
#==============================================================================
$ErrorActionPreference = "Stop"

#------------------------------------------------------------------------------
# 路径定义
#------------------------------------------------------------------------------
$proj  = "C:\Users\19117\Desktop\work\RISC-V\3_stage_pipeline"
$tcbin = "C:\Users\19117\Desktop\work\RISC-V\tools\xpack-riscv-none-elf-gcc-15.2.0-1\bin"
$src   = Join-Path $proj "freeRTOS\FreeRTOSv202411.00\FreeRTOS\Source"
$port  = Join-Path $src "portable\GCC\RISC-V"
$chip  = Join-Path $port "chip_specific_extensions\RISCV_MTIME_CLINT_no_extensions"
$app   = Join-Path $proj "freertos_app"
$build = Join-Path $app "build"
New-Item -ItemType Directory -Force -Path $build | Out-Null

$gcc     = Join-Path $tcbin "riscv-none-elf-gcc.exe"
$objcopy = Join-Path $tcbin "riscv-none-elf-objcopy.exe"
$size    = Join-Path $tcbin "riscv-none-elf-size.exe"

#------------------------------------------------------------------------------
# 编译选项
#------------------------------------------------------------------------------
# GCC 15 起 CSR 指令拆为独立 zicsr 扩展，需显式启用
$march = @("-march=rv32im_zicsr", "-mabi=ilp32")
$inc   = @("-I$(Join-Path $src 'include')", "-I$port", "-I$app")

# C 编译选项：-Os 控制体积；-ffunction-sections 配合 gc-sections 剔除未用代码
$cflags = $march + $inc + @(
    "-ffreestanding", "-nostdlib", "-fno-builtin",
    "-Os", "-Wall", "-Wextra",
    "-mno-relax",
    "-fdata-sections", "-ffunction-sections"
)

# 汇编选项：汇编器 include 路径让 portASM.S 找到芯片扩展头与 portContext.h
$asflags = $march + @("-I$port", "-I$chip", "-x", "assembler-with-cpp")

#------------------------------------------------------------------------------
# 源文件（精简：仅 tasks/queue/list + RISC-V 端口 + heap_4 + 应用）
#------------------------------------------------------------------------------
$cfiles = @(
    (Join-Path $src "tasks.c"),
    (Join-Path $src "queue.c"),
    (Join-Path $src "list.c"),
    (Join-Path $port "port.c"),
    (Join-Path $src "portable\MemMang\heap_4.c"),
    (Join-Path $app "main.c"),
    (Join-Path $app "support.c")
)
$sfiles = @(
    (Join-Path $port "portASM.S"),
    (Join-Path $app "startup.S")
)

#------------------------------------------------------------------------------
# 编译 C 源
#------------------------------------------------------------------------------
foreach ($c in $cfiles) {
    $o = Join-Path $build ([IO.Path]::GetFileNameWithoutExtension($c) + ".o")
    Write-Host "CC  $([IO.Path]::GetFileName($c))"
    & $gcc @cflags -c $c -o $o
}

#------------------------------------------------------------------------------
# 汇编
#------------------------------------------------------------------------------
foreach ($s in $sfiles) {
    $o = Join-Path $build ([IO.Path]::GetFileNameWithoutExtension($s) + ".o")
    Write-Host "AS  $([IO.Path]::GetFileName($s))"
    & $gcc @asflags -c $s -o $o
}

#------------------------------------------------------------------------------
# 链接（--gc-sections 剔除未引用段；.probe 与 .text.init 已 KEEP 保留）
#------------------------------------------------------------------------------
$objs = Get-ChildItem -LiteralPath $build -Filter *.o | ForEach-Object { $_.FullName }
$elf  = Join-Path $build "firmware.elf"
Write-Host "LINK firmware.elf"
& $gcc @march -nostdlib -T (Join-Path $app "link.ld") "-Wl,--gc-sections" $objs -o $elf

# 段尺寸统计
& $size $elf

#------------------------------------------------------------------------------
# 直接从 ELF 按 LMA 提取 IMEM 镜像并转换为仿真 hex
#------------------------------------------------------------------------------
python (Join-Path $app "elf2hex.py") $elf (Join-Path $build "firmware.hex") 16384

Write-Host "BUILD DONE -> $build\firmware.hex"
