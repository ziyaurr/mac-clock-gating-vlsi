"""
parse_power.py
Parses Vivado `report_power` text output for all four designs in this
project and prints a comparison table with savings relative to the
ungated baseline.

FIX (unchanged from the original single-comparison version): the naive
regex (`Total On-Chip Power.*?=\\s+([\\d.]+)\\s+W`) assumed an "=" style
report line, but Vivado's report_power prints a pipe-delimited table
(`| Total On-Chip Power (W)  | 0.124 |`), so that pattern never matched.
Fixed below to match Vivado's real table format.
"""
import re
from pathlib import Path

REPORTS = [
    ("Baseline (ungated)",             "power_report_baseline.txt"),
    ("Vivado auto clock gating",       "power_report_auto_cg.txt"),
    ("Manual single-stage ICG",        "power_report_manual_cg.txt"),
    ("Pipelined + operand isolation",  "power_report_pipelined.txt"),
]


def _extract(content, pattern):
    match = re.search(pattern, content, re.MULTILINE)
    return float(match.group(1)) if match else None


def parse_power(filename):
    path = Path(filename)
    if not path.exists():
        return None, None
    content = path.read_text()
    total = _extract(content, r'Total On-Chip Power\s*\(W\)\s*\|\s*([\d.]+)')
    dynamic = _extract(content, r'^\s*\|\s*Dynamic\s*\(W\)\s*\|\s*([\d.]+)')
    if dynamic is None:
        dynamic = _extract(content, r'^\s*\|\s*Dynamic\s*\|\s*([\d.]+)')
    return total, dynamic


def main():
    results = []
    for label, fname in REPORTS:
        total, dynamic = parse_power(fname)
        results.append((label, fname, total, dynamic))

    baseline_dynamic = results[0][3]

    print(f"{'Design':<32} {'Total (mW)':>11} {'Dynamic (mW)':>13} {'Savings vs baseline':>20}")
    print("-" * 80)
    for label, fname, total, dynamic in results:
        if total is None:
            print(f"{label:<32} {'N/A':>11} {'N/A':>13} {'(missing ' + fname + ')':>20}")
            continue
        total_mw = total * 1000
        dyn_mw = dynamic * 1000 if dynamic is not None else float('nan')
        if baseline_dynamic and dynamic is not None:
            savings = (1 - dynamic / baseline_dynamic) * 100
            savings_str = f"{savings:6.1f}%"
        else:
            savings_str = "N/A"
        print(f"{label:<32} {total_mw:11.2f} {dyn_mw:13.2f} {savings_str:>20}")


if __name__ == "__main__":
    main()
