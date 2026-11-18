set fpga_dir "C:/Users/19117/Desktop/work/RISC-V/3_stage_pipeline/fpga"
open_project [file join $fpga_dir RISCV.xpr]

puts "==== ALL FILES ===="
foreach f [get_files] {
    puts "FILE: $f"
    puts "   file_type = [get_property file_type $f]"
    puts "   is_global = [get_property is_global_include $f]"
}

puts "==== match test ===="
puts "match */riscv_defines.svh -> [get_files -quiet */riscv_defines.svh]"
close_project
