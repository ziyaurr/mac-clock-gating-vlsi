# xsim_saif.tcl
# Xilinx-native SAIF capture for tb_activity_sweep (drives all THREE
# design variants with identical stimulus), used as a fallback/alternative
# to the $toggle_start/$toggle_stop/$toggle_report tasks in tb_mac.v
# (those are IEEE PLI tasks that XSIM's documented flow does not rely on;
# XSIM's own SAIF flow is Tcl-command based, shown here).
#
# Usage (elaborate the sim_sweep simset first, e.g.
# `launch_simulation -simset sim_sweep -mode behav`, then from the Tcl
# console, or via `xsim tb_activity_sweep_behav -tclbatch scripts/xsim_saif.tcl`):
#
# Pass the activity factor via a plusarg when launching xsim, e.g.:
#   xsim tb_activity_sweep_behav -testplusarg "EN_PROB=30" \
#       -tclbatch scripts/xsim_saif.tcl

restart
;# Always start SAIF capture from time 0, regardless of whether
;# launch_simulation already auto-ran the sim for its configured runtime
;# before you got to this script (avoids silently missing early toggles).

open_saif mac_power.saif

# Log all three DUT instances so read_saif's -strip_path can pick out
# whichever one matches the currently open implemented design.
log_saif [get_objects -r /tb_activity_sweep/u_baseline/*]
log_saif [get_objects -r /tb_activity_sweep/u_cg/*]
log_saif [get_objects -r /tb_activity_sweep/u_pipe/*]

run all

close_saif

puts "SAIF capture complete: mac_power.saif"
