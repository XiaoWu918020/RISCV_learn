# sim_board_post_synth.tcl —— 对当前 status 设计运行整板综合后功能仿真
set fpga_dir "C:/Users/19117/Desktop/work/RISC-V/3_stage_pipeline/fpga"
set tb_file  "C:/Users/19117/Desktop/work/RISC-V/3_stage_pipeline/tb/tb_board_netlist.sv"
open_project [file join $fpga_dir RISCV.xpr]
add_files -fileset sim_1 -norecurse $tb_file
set_property top tb_board_netlist [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {50us} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -mode post-synthesis -type functional
close_sim -quiet
close_project
puts "INFO: POST SYNTH BOARD SIM DONE"
