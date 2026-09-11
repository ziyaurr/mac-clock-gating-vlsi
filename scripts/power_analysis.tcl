proc report_one {run_name out_file report_name} {
    open_run $run_name
    
    # Virtual clock define karein
    create_clock -name clk -period 10.000
    
    # Read SAIF without strict hierarchical prefix stripping
read_saif -strip_path tb_activity_sweep/u_baseline "D:/New_folder/mac_clock_gating_project/mac_clock_gating_project/mac_clock_gating/mac_clock_gating.sim/sim_sweep/behav/xsim/mac_power.saif"    
    report_power -file $out_file -name $report_name
    close_design
}

report_one impl_2 power_report_baseline.txt   {Baseline (ungated)}
report_one impl_3 power_report_auto_cg.txt    {Vivado auto clock gating}
report_one impl_1 power_report_manual_cg.txt {Manual single-stage ICG}
report_one impl_4 power_report_pipelined.txt {Pipelined + operand isolation}

puts "Power analysis complete!"