# Primary clock
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

# FIX: declare the internally-generated gated clock. Without this, Vivado
# has no timing relationship for gated_clk (produced by u_cg), which can
# throw "unconstrained clock" DRC warnings during implementation and can
# skew the clock-tree portion of the power report for the gated design.
# This assumes top = mac_unit_cg, so the gating cell instance is u_cg.
create_generated_clock -name gated_clk \
    -source [get_pins u_cg/clk] \
    -divide_by 1 \
    [get_pins u_cg/gated_clk]

# FIX: the original pattern `*clock_gating_cell*` matches against the
# INSTANCE name, but the instance is actually called `u_cg` (see
# mac_unit_cg.v) — "u_cg" does not contain the substring
# "clock_gating_cell", so this DONT_TOUCH previously matched ZERO cells
# and silently failed to protect the gating cell from being optimized
# away, defeating the point of the whole exercise. Matching by REF_NAME
# (the module/cell type) instead is robust no matter what the instance
# is named.
set_property DONT_TOUCH true [get_cells -hierarchical -filter {REF_NAME == clock_gating_cell}]
set_property DONT_TOUCH true [get_nets -hierarchical *gated_clk*]
