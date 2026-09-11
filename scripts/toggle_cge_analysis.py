#!/usr/bin/env python3
"""
toggle_cge_analysis.py

Runs tb_activity_sweep.sv at a range of activity factors (en=1 probability,
0-100%) using Icarus Verilog, parses the resulting VCD to count REAL
rising-edge (toggle) counts on the reference clock and on each gated
clock, computes Clock Gating Efficiency (CGE) at each point, writes a CSV,
and plots CGE vs activity factor for both gating strategies in this
project:

    CGE = 1 - (rising_edges(gated_clk) / rising_edges(clk))

This is a tool-independent, directly-measurable proxy for the dynamic
power savings a Vivado SAIF/report_power flow would report for the
register bank behind that clock -- fewer real clock edges reaching a
register means less switched capacitance means less dynamic power. It
doesn't replace a real Vivado power report (that also accounts for
combinational toggling, routing capacitance, static power, etc. -- see
scripts/power_analysis.tcl for that), but it's something we can actually
compute and verify right now, with only open-source tools.

Usage:
    python3 scripts/toggle_cge_analysis.py
Requires: iverilog, vvp on PATH; matplotlib for the plot (falls back to
CSV-only if matplotlib isn't installed).
"""
import re
import subprocess
import sys
import csv
import shutil
from pathlib import Path

SRC_DIR = Path(__file__).resolve().parent.parent / "src"
WORK_DIR = Path("./tmp_cge_sweep")
WORK_DIR.mkdir(exist_ok=True)

SIM_BIN = WORK_DIR / "sweep.out"
VCD_PATH = Path("activity_sweep.vcd")  # written by $dumpfile in the testbench, in CWD

TOP = "tb_activity_sweep"
TARGETS = {
    "clk":          f"{TOP}.clk",
    "gated_clk_cg": f"{TOP}.u_cg.gated_clk",
    "gated_clk_s1": f"{TOP}.u_pipe.gated_clk_s1",
    "gated_clk_s2": f"{TOP}.u_pipe.gated_clk_s2",
}
BUS_TARGETS = {
    "mult_baseline": f"{TOP}.u_baseline.mult",  
    "mult_pipe":     f"{TOP}.u_pipe.mult",        
}

ACTIVITY_FACTORS = list(range(0, 101, 10))  


def find_executable(exe_name):
    """Finds executable in your custom folder or system PATH."""
    custom_path = Path(r"C:\iverilog-13_0\iverilog-13_0\bin") / f"{exe_name}.exe"
    if custom_path.exists():
        return str(custom_path)
        
    exe = shutil.which(exe_name)
    if exe:
        return exe
    
    windows_fallbacks = [
        Path(f"C:/iverilog/bin/{exe_name}.exe"),
        Path(f"C:/Program Files/Icarus Verilog/bin/{exe_name}.exe"),
        Path(f"C:/Program Files (x86)/Icarus Verilog/bin/{exe_name}.exe"),
    ]
    for path in windows_fallbacks:
        if path.exists():
            return str(path)
            
    return None


def compile_sim():
    sources = [
        "mac_unit.v", "clock_gating_cell.v", "mac_unit_cg.v",
        "mac_unit_pipelined_cg.v", "tb_activity_sweep.sv",
    ]
    
    iverilog_bin = find_executable("iverilog")
    if not iverilog_bin:
        raise FileNotFoundError(
            "Could not find 'iverilog' executable. Please make sure Icarus Verilog is installed "
            "at C:\\iverilog-13_0\\iverilog-13_0 or added to your system PATH."
        )
        
    cmd = [iverilog_bin, "-g2012", "-o", str(SIM_BIN)] + [str(SRC_DIR / s) for s in sources]
    subprocess.run(cmd, check=True)


def run_and_count(en_prob):
    vvp_bin = find_executable("vvp") or "vvp"
    # Use SIM_BIN.name since cwd is already WORK_DIR to prevent path nesting issues
    subprocess.run([vvp_bin, SIM_BIN.name, f"+EN_PROB={en_prob}"],
                    check=True, cwd=WORK_DIR, stdout=subprocess.DEVNULL)
    vcd_file = WORK_DIR / VCD_PATH
    clock_counts = count_rising_edges(vcd_file, TARGETS)
    bus_counts = count_all_changes(vcd_file, BUS_TARGETS)
    return clock_counts, bus_counts


def _build_id_map(vcd_file):
    name_to_id = {}
    scope_stack = []
    with open(vcd_file, "r", errors="ignore") as f:
        lines = f.readlines()

    body_start = 0
    for idx, raw in enumerate(lines):
        line = raw.strip()
        if line.startswith("$scope"):
            scope_stack.append(line.split()[2])
        elif line.startswith("$upscope"):
            scope_stack.pop()
        elif line.startswith("$var"):
            parts = line.split()
            sig_id, sig_name = parts[3], parts[4]
            name_to_id[".".join(scope_stack + [sig_name])] = sig_id
        elif line.startswith("$enddefinitions"):
            body_start = idx + 1
            break
    return name_to_id, lines, body_start


def count_rising_edges(vcd_file, targets):
    name_to_id, lines, body_start = _build_id_map(vcd_file)
    id_to_label = {}
    for label, path in targets.items():
        if path not in name_to_id:
            raise RuntimeError(f"Signal not found in VCD: {path}")
        id_to_label[name_to_id[path]] = label

    counts = {label: 0 for label in targets}
    for line in lines[body_start:]:
        line = line.rstrip("\n")
        if not line or line[0] not in "01xzXZ":
            continue
        val, sig_id = line[0], line[1:]
        if val == "1" and sig_id in id_to_label:
            counts[id_to_label[sig_id]] += 1
    return counts


def count_all_changes(vcd_file, targets):
    name_to_id, lines, body_start = _build_id_map(vcd_file)
    id_to_label = {}
    for label, path in targets.items():
        if path not in name_to_id:
            raise RuntimeError(f"Signal not found in VCD: {path}")
        id_to_label[name_to_id[path]] = label

    counts = {label: 0 for label in targets}
    for line in lines[body_start:]:
        line = line.rstrip("\n")
        if not line:
            continue
        if line[0] == "b":
            parts = line.split(" ")
            if len(parts) == 2 and parts[1] in id_to_label:
                counts[id_to_label[parts[1]]] += 1
        elif line[0] in "01xzXZ":
            sig_id = line[1:]
            if sig_id in id_to_label:
                counts[id_to_label[sig_id]] += 1
    return counts


def main():
    print("Compiling activity-sweep testbench...")
    compile_sim()

    rows = []
    for af in ACTIVITY_FACTORS:
        clock_counts, bus_counts = run_and_count(af)
        clk_edges = clock_counts["clk"]
        cge_single = 1 - clock_counts["gated_clk_cg"] / clk_edges if clk_edges else 0.0
        cge_s1 = 1 - clock_counts["gated_clk_s1"] / clk_edges if clk_edges else 0.0
        cge_s2 = 1 - clock_counts["gated_clk_s2"] / clk_edges if clk_edges else 0.0
        mult_baseline = bus_counts["mult_baseline"]
        mult_pipe = bus_counts["mult_pipe"]
        mult_reduction = (1 - mult_pipe / mult_baseline) if mult_baseline else 0.0
        rows.append({
            "activity_factor_pct": af,
            "clk_edges": clk_edges,
            "gated_clk_cg_edges": clock_counts["gated_clk_cg"],
            "gated_clk_s1_edges": clock_counts["gated_clk_s1"],
            "gated_clk_s2_edges": clock_counts["gated_clk_s2"],
            "cge_single_stage_pct": round(cge_single * 100, 2),
            "cge_pipelined_s1_pct": round(cge_s1 * 100, 2),
            "cge_pipelined_s2_pct": round(cge_s2 * 100, 2),
            "mult_toggles_baseline": mult_baseline,
            "mult_toggles_isolated": mult_pipe,
            "operand_isolation_reduction_pct": round(mult_reduction * 100, 2),
        })
        print(f"EN_PROB={af:3d}%  "
              f"CGE(single-stage)={rows[-1]['cge_single_stage_pct']:6.2f}%  "
              f"CGE(pipe s1)={rows[-1]['cge_pipelined_s1_pct']:6.2f}%  "
              f"CGE(pipe s2)={rows[-1]['cge_pipelined_s2_pct']:6.2f}%  "
              f"mult-toggle-reduction={rows[-1]['operand_isolation_reduction_pct']:6.2f}%")

    out_csv = Path(__file__).resolve().parent.parent / "results" / "cge_sweep.csv"
    out_csv.parent.mkdir(exist_ok=True)
    with open(out_csv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nWrote {out_csv}")

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt

        afs = [r["activity_factor_pct"] for r in rows]
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(12, 5))

        ax1.plot(afs, [r["cge_single_stage_pct"] for r in rows],
                 marker="o", label="Single-stage ICG (mac_unit_cg)")
        ax1.plot(afs, [r["cge_pipelined_s1_pct"] for r in rows],
                 marker="s", label="Pipelined stage 1 (mult reg)")
        ax1.plot(afs, [r["cge_pipelined_s2_pct"] for r in rows],
                 marker="^", label="Pipelined stage 2 (acc reg)")
        ax1.set_xlabel("Activity factor -- P(en=1) (%)")
        ax1.set_ylabel("Clock Gating Efficiency, CGE (%)")
        ax1.set_title("Register clock-toggle savings")
        ax1.grid(True, alpha=0.3)
        ax1.legend()

        ax2.plot(afs, [r["operand_isolation_reduction_pct"] for r in rows],
                 marker="d", color="tab:red",
                 label="Multiplier toggle reduction (operand isolation)")
        ax2.set_xlabel("Activity factor -- P(en=1) (%)")
        ax2.set_ylabel("Combinational toggle reduction (%)")
        ax2.set_title("Multiplier switching-activity savings\n(not visible in clock-based CGE)")
        ax2.grid(True, alpha=0.3)
        ax2.legend()

        plt.suptitle("Measured directly from VCD toggle counts (Icarus Verilog)")
        plt.tight_layout()
        out_png = out_csv.parent / "cge_sweep.png"
        plt.savefig(out_png, dpi=150)
        print(f"Wrote {out_png}")
    except ImportError:
        print("matplotlib not installed -- skipping plot, CSV is still written.")


if __name__ == "__main__":
    main()