# constraints_baseline.xdc
# Used for BOTH the plain ungated baseline (impl_2, top=mac_unit) and the
# Vivado-automatic-clock-gating run (impl_3, same top=mac_unit but with
# STEPS.POWER_OPT_DESIGN.IS_ENABLED=true — see create_project.tcl). No
# gating cell exists in this source, so there's nothing to DONT_TOUCH or
# declare a generated clock for; Vivado's own power_opt_design step is
# free to insert/remove any BUFGCE it likes on impl_3.
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

