# constraints_pipelined.xdc
# For impl_4, top = mac_unit_pipelined_cg. Two independent ICG cells
# (u_cg_s1, u_cg_s2) each need their own generated clock declared, same
# reasoning as constraints_cg.xdc's single one.
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

create_generated_clock -name gated_clk_s1 -source [get_pins u_cg_s1/clk] -divide_by 1 [get_pins u_cg_s1/gated_clk]

create_generated_clock -name gated_clk_s2 -source [get_pins u_cg_s2/clk] -divide_by 1 [get_pins u_cg_s2/gated_clk]

# Matches BOTH gating cell instances by module type (REF_NAME), same fix
# as constraints_cg.xdc — instance names don't matter.
set_property DONT_TOUCH true [get_cells -hierarchical -filter {REF_NAME == clock_gating_cell}]
set_property DONT_TOUCH true [get_nets -hierarchical *gated_clk*]

create_clock -period 10.000 -name clk [get_ports clk]
reset_switching_activity -all 
