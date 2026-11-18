#==============================================================================
# build_min.ps1 —— 构建最小裸机固件（min_main + 现有 startup/link.ld/elf2hex）
# 产出 build\min.hex，供综合时作为 IMEM 初始化文件
#==============================================================================
$ErrorActionPreference = "Stop"

$proj   = "C:\Users\19117\Desktop\work\RISC-V\3_stage_pipeline"
$tcbin  = "C:\Users\19117\Desktop\work\RISC-V\tools\xpack-riscv-none-elf-gcc-15.2.0-1\bin"
$app    = Join-Path $proj "freertos_app"          # 复用 startup.S / link.ld / elf2hex.py
$here   = Join-Path $proj "fpga\baremetal_min"
$build  = Join-Path $here "build"
New-Item -ItemType Directory -Force -Path $build | Out-Null

$gcc  = Join-Path $tcbin "riscv-none-elf-gcc.exe"
$size = Join-Path $tcbin "riscv-none-elf-size.exe"

$march   = @("-march=rv32im_zicsr", "-mabi=ilp32")
$cflags  = $march + @(
    "-ffreestanding", "-nostdlib", "-fno-builtin",
    "-Os", "-Wall", "-Wextra", "-mno-relax",
    "-fdata-sections", "-ffunction-sections"
)
$asflags = $march + @("-x", "assembler-with-cpp")

# 1. 编译最小 C 程序
& $gcc @cflags -c (Join-Path $here "min_main.c") -o (Join-Path $build "min_main.o")
# 2. 汇编现有启动代码
& $gcc @asflags -c (Join-Path $app "startup.S") -o (Join-Path $build "startup.o")

# 3. 链接（复用同一 link.ld，--gc-sections）
$elf = Join-Path $build "min.elf"
& $gcc @march -nostdlib -T (Join-Path $app "link.ld") "-Wl,--gc-sections" `
      (Join-Path $build "min_main.o") (Join-Path $build "startup.o") -o $elf
& $size $elf

# 4. 生成扁平 hex（IMEM 16KB = 16384 字节）
python (Join-Path $app "elf2hex.py") $elf (Join-Path $build "min.hex") 16384
Write-Host "MIN BUILD DONE -> $build\min.hex"
