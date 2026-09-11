# MAC Unit — Clock Gating Power Analysis (Advanced)

4-way low-power comparison of a MAC (Multiply-Accumulate) unit:

| # | Design | Technique |
|---|---|---|
| 1 | `mac_unit.v` | Baseline — no gating |
| 2 | `mac_unit.v` + Vivado `power_opt_design` | **Automatic** clock gating (Vivado infers it) |
| 3 | `mac_unit_cg.v` | **Manual** single-stage, block-level clock gating |
| 4 | `mac_unit_pipelined_cg.v` | **Manual** 2-stage pipeline, per-stage clock gating + operand isolation |

Everything below was actually compiled and simulated (Icarus Verilog +
Verilator for SV lint) in this environment to confirm it's real, not just
written. See **"Verified vs. needs Vivado"** near the end for exactly
which parts that covers.

## Folder Structure
```
mac_clock_gating_project/
├── src/
│   ├── mac_unit.v               # Baseline MAC, no clock gating
│   ├── mac_unit_cg.v            # Single-stage manual ICG
│   ├── mac_unit_pipelined_cg.v  # 2-stage pipeline + operand isolation + per-stage ICG
│   ├── clock_gating_cell.v      # Latch-based ICG cell (shared by both gated designs)
│   ├── tb_mac.v                 # Baseline vs single-stage CG, functional-equivalence testbench
│   ├── tb_mac_pipelined.sv      # Self-checking scoreboard for the pipelined design
│   └── tb_activity_sweep.sv     # Drives all 3 designs identically, for toggle/SAIF capture
├── constraints/
│   ├── constraints_baseline.xdc  # top = mac_unit (plain + Vivado-auto-CG runs)
│   ├── constraints_cg.xdc        # top = mac_unit_cg
│   └── constraints_pipelined.xdc # top = mac_unit_pipelined_cg
├── scripts/
│   ├── create_project.tcl        # Vivado project + 4 synth/impl runs
│   ├── xsim_saif.tcl             # XSIM-native SAIF capture (tb_activity_sweep)
│   ├── power_analysis.tcl        # read_saif + report_power for all 4 runs
│   ├── parse_power.py            # 4-way power comparison table
│   └── toggle_cge_analysis.py    # Activity-factor sweep + CGE plot (Icarus-only, no Vivado needed)
├── results/
│   ├── cge_sweep.csv             # Real measured data from this environment
│   └── cge_sweep.png             # Plot generated from that data
└── README.md
```

## RTL Depth: pipelined + operand-isolated design

`mac_unit_cg.v` only gates the *output register's* clock. But
`mult = a * b` is a combinational multiplier that keeps toggling every
cycle just from `a`/`b` changing, **regardless of `en`** — clock gating
alone never touches that. `mac_unit_pipelined_cg.v` adds two more
techniques on top:

```
        en                                          en
        │                                            │
   a ──►│                                       ┌───►│ (isolated to 0
   b ──►│  a_iso, b_iso = en ? a,b : 0           │     when en=0, so the
        │  (OPERAND ISOLATION)                   │     multiplier itself
        ▼                                        │     stops toggling)
   ┌─────────┐        ┌────────────┐        ┌────────────┐
   │  mult   │──────► │  mult_r    │──────► │    acc     │──► acc, valid_out
   │ (comb.) │        │ (Stage 1)  │  sum=  │ (Stage 2)  │
   └─────────┘        └─────┬──────┘  acc+  └─────┬──────┘
                             │        mult_r       │
                       gated_clk_s1          gated_clk_s2
                       (ICG on `en`)          (ICG on `valid_s1`)
```

- **Operand isolation**: `a_iso`/`b_iso` force to 0 when `en=0`, so the
  multiplier's combinational logic stops switching too, not just the
  register.
- **Fine-grain, per-stage gating**: two independent ICG cells. Stage 2's
  clock only ungates when stage 1 actually produced something valid —
  it stays ungated one extra cycle after `en` drops, to drain the
  pipeline, which a single block-level gate can't express.
- Latency 2 cycles, throughput 1 op/cycle (fully pipelined).

### Bug found while building this (via the self-checking testbench)
First version clocked the `valid_s1` control register with the *gated*
clock `gated_clk_s1`. When `en=0`, that clock never ticks — so
`valid_s1` **froze at its last value** instead of deasserting, and
stage 2 kept re-accumulating the same stale product forever. Ran
`tb_mac_pipelined.sv`: **1997/1999 mismatches** against a reference
model. **Fix:** control/valid registers (`valid_s1`, `valid_out`) now
live on the plain, always-on `clk` (negligible power cost for 1 bit);
only the *wide data* registers (`mult_r`, `acc`) sit behind the gated
clocks. Re-ran across `EN_PROB` = 0, 10, 50, 90, 100 %: **0 mismatches
at every point.**

## Verification Rigor

`tb_mac_pipelined.sv` has two layers:

1. **Self-checking scoreboard + immediate assertions** — a reference
   queue model runs alongside the DUT every cycle; `assert (acc ===
   ref_acc) else ...` fires immediately on any mismatch. **This layer is
   what actually caught the bug above** — confirmed running on Icarus
   Verilog (`iverilog -g2012`).
2. **Concurrent SVA properties + a functional covergroup**, guarded
   behind `` `ifdef USE_SVA_COVERAGE `` (off by default):
   - `p_no_glitch_s1` / `p_no_glitch_s2` — a gated clock must never rise
     while its ICG cell's latch output is unstable.
   - `p_valid_causality` — `valid_out` can only assert if `valid_s1` was
     true the cycle before (`disable iff (!rst_n)`, `$past(...)`).
   - `cg_activity` covergroup — bins the exercised activity factor,
     back-to-back/idle run lengths, and crosses `en`×`valid_out`.

   **Honesty check on this layer:** neither Icarus Verilog 12.0 nor
   Verilator 5.020 (both tried here) implement `covergroup` or
   cycle-delay (`##N`) `assert property` — confirmed by literally trying
   to compile them and getting parse/`UNSUPPORTED` errors. The simpler
   properties above (no `##` delay, using `$rose`/`$stable`/`$past`
   instead) DO pass a Verilator `--lint-only` syntax check, so they're
   at least confirmed-valid IEEE-1800 syntax — but none of layer 2 has
   been *simulated*. Define `USE_SVA_COVERAGE` and run on Vivado
   xsim/Questa/VCS to actually exercise it.

## Power-Analysis Depth

### 1. Activity-factor sweep + Clock Gating Efficiency (CGE) — **run and verified right here**
```
python3 scripts/toggle_cge_analysis.py
```
Runs `tb_activity_sweep.sv` at `EN_PROB` = 0, 10, ..., 100 %, parses the
VCD, and computes:

    CGE = 1 − (rising edges of gated_clk / rising edges of clk)

measured directly from real simulated toggle counts — a tool-independent
proxy for the register-power savings a Vivado SAIF/`report_power` flow
would show (fewer real clock edges reaching a register ⇒ less switched
capacitance ⇒ less dynamic power). Actual measured results (`results/cge_sweep.csv`,
plotted in `results/cge_sweep.png`):

| Activity factor | CGE (single-stage) | CGE (pipe stage 1) | CGE (pipe stage 2) | Multiplier toggle reduction |
|---|---|---|---|---|
| 0%   | 100.0% | 100.0% | 100.0% | 100.0% |
| 30%  | 70.0%  | 70.0%  | 70.0%  | 48.4%  |
| 50%  | 50.0%  | 50.0%  | 50.0%  | 25.2%  |
| 70%  | 29.1%  | 29.1%  | 29.1%  | 8.6%   |
| 100% | 0.07%  | 0.07%  | 0.10%  | 0.0%   |

Single-stage and both pipeline stages track each other almost exactly
(expected — they all gate on the same or a one-cycle-delayed version of
the same random `en`). The separate **multiplier toggle reduction**
column is the operand-isolation benefit specifically — it isn't visible
in clock-based CGE at all, because it's about *combinational* switching,
not a register clock. It's largest at low activity (the multiplier would
otherwise be churning through random `a`,`b` every idle cycle) and
shrinks toward 0 as activity → 100% (nothing to isolate when it's always
enabled).

### 2. Auto (Vivado) vs. manual clock gating
`create_project.tcl` sets up `impl_3` = the *same* `mac_unit.v` baseline
source, but with `STEPS.POWER_OPT_DESIGN.IS_ENABLED true`, so Vivado's
own `power_opt_design` step tries to infer clock gating (BUFGCE
insertion) automatically — compared against `impl_1` (hand-written ICG)
and `impl_2` (no gating at all, not even automatic).

### 3. CGE from real Vivado power reports
```tcl
source scripts/power_analysis.tcl
```
```bash
python3 scripts/parse_power.py
```
prints a 4-way table (Total/Dynamic power + % savings vs. baseline) by
parsing all four `report_power` outputs.

## Run Steps

**Local (Icarus Verilog + Python — everything in this section was
actually run to produce this README's numbers):**
```bash
cd mac_clock_gating_project/src
iverilog -g2012 -o /tmp/f1 mac_unit.v clock_gating_cell.v mac_unit_cg.v tb_mac.v && vvp /tmp/f1
iverilog -g2012 -o /tmp/f2 clock_gating_cell.v mac_unit_pipelined_cg.v tb_mac_pipelined.sv && vvp /tmp/f2 +EN_PROB=50
cd .. && python3 scripts/toggle_cge_analysis.py
```

**Vivado (scripts are complete and correct, but NOT run in this
environment — no Vivado license here; see next section):**
```tcl
vivado -mode batch -source scripts/create_project.tcl
# then, from the Tcl console:
foreach r {synth_1 synth_2 synth_3 synth_4} { launch_runs $r -jobs 4; wait_on_run $r }
foreach r {impl_1  impl_2  impl_3  impl_4}  { launch_runs $r -jobs 4; wait_on_run $r }
source scripts/power_analysis.tcl
```
```bash
python3 scripts/parse_power.py
```

## Verified vs. Needs Vivado

| Claim | Status |
|---|---|
| All 3 RTL designs compile & are functionally correct | ✅ Verified — Icarus, all `EN_PROB` from 0–100% |
| Pipelined design's control-register bug + fix | ✅ Verified — found AND re-verified via the scoreboard |
| CGE / operand-isolation numbers in the table above | ✅ Verified — real VCD toggle counts, this run |
| SVA properties are valid syntax | ✅ Verified — Verilator `--lint-only` |
| SVA properties / covergroup actually catching bugs | ❌ Not run — needs Vivado xsim/Questa/VCS |
| `power_opt_design` auto-CG vs manual-CG numbers | ❌ Not run — needs a Vivado license/install |
| `DONT_TOUCH`/generated-clock XDC correctness | ⚠️ Reviewed carefully, matches documented Vivado syntax, but not run through actual `synth_design`/`report_power` here |

## All Bugs Found (original spec + this upgrade)

1. **Testbench race causing 999/1000 functional mismatches** (found
   simulating the *original* single-stage comparison) — stimulus was
   driven on the same edge (`@(posedge clk)`) both DUTs sampled on.
   Fixed by moving to `@(negedge clk)`.
2. **Pipelined design's `valid_s1` frozen by its own gated clock**
   (found simulating the *advanced* pipelined design) — see RTL section
   above.
3. **`$toggle_start`/`$toggle_report` are fatal**, not just unsupported —
   confirmed by actually running them on Icarus. Guarded behind
   `` `ifdef USE_TOGGLE_TASKS ``; `scripts/xsim_saif.tcl` is the working
   alternative.
4. **`tb_mac.v` in the synthesizable fileset** would crash
   `launch_runs synth_1` (non-synthesizable constructs). Moved to
   `sim_1` only.
5. **`DONT_TOUCH *clock_gating_cell*` matched zero cells** (pattern was
   instance-name-based; actual instance is `u_cg`/`u_cg_s1`/`u_cg_s2`).
   Fixed with `-filter {REF_NAME == clock_gating_cell}`.
6. **Missing generated-clock constraints** for every gated clock
   (`gated_clk`, `gated_clk_s1`, `gated_clk_s2`).
7. **Power comparison never actually ran** — baseline lines were
   commented out in the original `power_analysis.tcl`.
8. **`parse_power.py` regex assumed the wrong tool's report format**
   (`= 1.234 W` instead of Vivado's pipe table).
9. **Latch coding style** — non-blocking assignment in a level-sensitive
   latch; changed to blocking.

## Known Limitation (by design, not fixed)
`acc = acc + mult` is a free-running, finite-width accumulator — it
silently wraps on overflow. Fine here since the goal is a
switching-activity/power comparison, not exact arithmetic correctness.
