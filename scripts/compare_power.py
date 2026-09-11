import re
from pathlib import Path

reports = {
    "Baseline (Ungated)": "power_report_baseline.txt",
    "Auto CG": "power_report_auto_cg.txt",
    "Manual ICG": "power_report_manual_cg.txt",
    "Pipelined + Iso": "power_report_pipelined.txt"
}

print(f"{'Strategy':<20} | {'Total Power (W)':<18} | {'Dynamic (W)':<15} | {'Clocks (W)':<12}")
print("-" * 75)

for name, filename in reports.items():
    path = Path(filename)
    if not path.exists():
        print(f"{name:<20} | Report not found")
        continue
        
    content = path.read_text(errors="ignore")
    total_p, dyn_p, clk_p = "N/A", "N/A", "N/A"
    
    for line in content.splitlines():
        if "Total On-Chip Power" in line:
            nums = re.findall(r"\d+\.\d+", line)
            if nums:
                total_p = nums[0]
        elif "Dynamic" in line and dyn_p == "N/A":
            nums = re.findall(r"\d+\.\d+", line)
            if nums:
                dyn_p = nums[0]
        elif "Clocks" in line and clk_p == "N/A":
            nums = re.findall(r"\d+\.\d+", line)
            if nums:
                clk_p = nums[0]
                
    print(f"{name:<20} | {total_p:<18} | {dyn_p:<15} | {clk_p:<12}")