# build_diag2.ps1 —— 构建 UART 读写诊断固件，产出 build\diag2.hex
$ErrorActionPreference = "Stop"

$proj   = "C:\Users\19117\Desktop\work\RISC-V\3_stage_pipeline"
$tcbin  = "C:\Users\19117\Desktop\work\RISC-V\tools\xpack-riscv-none-elf-gcc-15.2.0-1\bin"
$app    = Join-Path $proj "freertos_app"
$here   = Join-Path $proj "fpga\baremetal_uart"
$build  = Join-Path $here "build"
New-Item -ItemType Directory -Force -Path $build | Out-Null

$gcc  = Join-Path $tcbin "riscv-none-elf-gcc.exe"
$size = Join-Path $tcbin "riscv-none-elf-size.exe"

$march  = @("-march=rv32im_zicsr", "-mabi=ilp32")
$cflags = $march + @(
    "-ffreestanding", "-nostdlib", "-fno-builtin",
    "-Os", "-Wall", "-Wextra", "-mno-relax",
    "-fdata-sections", "-ffunction-sections"
)
$asflags = $march + @("-x", "assembler-with-cpp")

& $gcc @cflags -c (Join-Path $here "diag2_main.c") -o (Join-Path $build "diag2_main.o")
& $gcc @asflags -c (Join-Path $app "startup.S") -o (Join-Path $build "startup.o")

$elf = Join-Path $build "diag2.elf"
& $gcc @march -nostdlib -T (Join-Path $app "link.ld") "-Wl,--gc-sections" `
      (Join-Path $build "diag2_main.o") (Join-Path $build "startup.o") -o $elf
& $size $elf

python (Join-Path $app "elf2hex.py") $elf (Join-Path $build "diag2.hex") 16384
Write-Host "DIAG2 BUILD DONE -> $build\diag2.hex"
