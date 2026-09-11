# Vivado Project Creation Script for MAC Clock Gating Analysis (ADVANCED)
# Usage: vivado -mode batch -source scripts/create_project.tcl
#
# Sets up a 4-way power comparison, all on the same part/clock period:
#   impl_1  top=mac_unit_cg             manual single-stage ICG
#   impl_2  top=mac_unit                ungated baseline
#   impl_3  top=mac_unit (same source)  Vivado AUTOMATIC clock gating
#                                        (power_opt_design infers it)
#   impl_4  top=mac_unit_pipelined_cg   manual pipelined + operand
#                                        isolation + per-stage ICG
#
# tb_mac.v stays SIM-ONLY (see the FIX note further down) and is not part
# of any synthesizable fileset.

set project_name "mac_clock_gating"
set project_dir  [file dirname [file normalize [info script]]]/..
set src_dir      $project_dir/src
set constr_dir   $project_dir/constraints

create_project -force $project_name $project_dir/$project_name -part xc7a35tcpg236-1

# Resolve the installed Vivado's actual synthesis/implementation flow
# names instead of hardcoding a version (e.g. "Vivado Synthesis 2023"),
# since that string changes every Vivado release and a hardcoded one
# breaks `create_run` on any other version.
set synth_flow [get_property FLOW [get_runs synth_1]]
set impl_flow  [get_property FLOW [get_runs impl_1]]
puts "Using flows: $synth_flow / $impl_flow"

# --- Design (synthesizable) sources: all four RTL modules live together;
# only the fileset TOP selects which one actually gets built for a given
# run. ---
add_files -fileset sources_1 [list \
    $src_dir/mac_unit.v \
    $src_dir/clock_gating_cell.v \
    $src_dir/mac_unit_cg.v \
    $src_dir/mac_unit_pipelined_cg.v \
]
set_property top mac_unit_cg [get_filesets sources_1]
update_compile_order -fileset sources_1

# --- Simulation sources (kept OUT of sources_1 -- see original project's
# critical bug #2: a testbench in the synthesizable fileset crashes
# `launch_runs synth_1` because of its non-synthesizable constructs). ---
add_files -fileset sim_1 $src_dir/tb_mac.v
set_property top tb_mac [get_filesets sim_1]

create_fileset -simset sim_pipelined
add_files -fileset sim_pipelined $src_dir/tb_mac_pipelined.sv
set_property top tb_mac_pipelined [get_filesets sim_pipelined]

create_fileset -simset sim_sweep
add_files -fileset sim_sweep $src_dir/tb_activity_sweep.sv
set_property top tb_activity_sweep [get_filesets sim_sweep]

foreach fs {sim_1 sim_pipelined sim_sweep} {
    set_property -name {xsim.simulate.runtime} -value {30us} -objects [get_filesets $fs]
}

# --- Three separate constraint filesets: baseline/CG/pipelined tops each
# need different (or no) generated-clock declarations, so they can't
# share one constrs_1 (see constraints/*.xdc comments for why). ---
create_fileset -constrset constrs_baseline
add_files -fileset constrs_baseline $constr_dir/constraints_baseline.xdc

create_fileset -constrset constrs_cg
add_files -fileset constrs_cg $constr_dir/constraints_cg.xdc

create_fileset -constrset constrs_pipelined
add_files -fileset constrs_pipelined $constr_dir/constraints_pipelined.xdc

# Default constrs_1 -> CG (matches the default sources_1 top above), so
# a plain `launch_runs synth_1` immediately after project creation works
# with no extra setup, same as the original (non-advanced) project did.
add_files -fileset constrs_1 $constr_dir/constraints_cg.xdc

puts "Project created. Setting up the 4 runs..."

# impl_1: manual single-stage ICG (created automatically as synth_1/impl_1
# using the default sources_1/constrs_1 above -- nothing extra to do).

# impl_2: ungated baseline
create_fileset -srcset sources_baseline
add_files -fileset sources_baseline [list \
    $src_dir/mac_unit.v \
    $src_dir/clock_gating_cell.v \
    $src_dir/mac_unit_cg.v \
    $src_dir/mac_unit_pipelined_cg.v \
]
set_property top mac_unit [get_filesets sources_baseline]
create_run synth_2 -flow $synth_flow -srcset sources_baseline -constrset constrs_baseline
create_run impl_2 -parent_run synth_2 -flow $impl_flow

# impl_3: SAME baseline source, Auto CG
create_run synth_3 -flow $synth_flow -srcset sources_baseline -constrset constrs_baseline
create_run impl_3 -parent_run synth_3 -flow $impl_flow
set_property STEPS.POWER_OPT_DESIGN.IS_ENABLED true [get_runs impl_3]

# impl_4: manual pipelined
create_fileset -srcset sources_pipelined
add_files -fileset sources_pipelined [list \
    $src_dir/mac_unit.v \
    $src_dir/clock_gating_cell.v \
    $src_dir/mac_unit_cg.v \
    $src_dir/mac_unit_pipelined_cg.v \
]
set_property top mac_unit_pipelined_cg [get_filesets sources_pipelined]
create_run synth_4 -flow $synth_flow -srcset sources_pipelined -constrset constrs_pipelined
create_run impl_4 -parent_run synth_4 -flow $impl_flow
puts "Done."
puts ""
puts "Simulation:"
puts "  launch_simulation; run all                          (tb_mac, 2 designs)"
puts "  launch_simulation -simset sim_pipelined -mode behav  (self-checking scoreboard)"
puts "  launch_simulation -simset sim_sweep -mode behav      (drives all 3 designs; use +EN_PROB=N)"
puts ""
puts "Synthesis + implementation (run all 4 for the full comparison):"
puts "  foreach r {synth_1 synth_2 synth_3 synth_4} { launch_runs \$r -jobs 4; wait_on_run \$r }"
puts "  foreach r {impl_1  impl_2  impl_3  impl_4}  { launch_runs \$r -jobs 4; wait_on_run \$r }"
puts ""
puts "Power comparison: source scripts/power_analysis.tcl"
