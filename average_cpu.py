import csv
from collections import defaultdict
import os

# Path to the CSV file
filename = 'validation/k3s_sample.csv'

# Dictionary to store a list of CPU values for each time step (t)
cpu_data = defaultdict(list)

print(f"Reading data from {filename}...\n")

if not os.path.exists(filename):
    print(f"Error: Could not find {filename}")
    exit(1)

with open(filename, 'r') as f:
    for line in f:
        line = line.strip()
        # Skip empty lines and headers
        if not line or line.startswith('t') or line.startswith('$t'):
            continue
        
        parts = line.split(',')
        if len(parts) >= 3:
            try:
                t = int(parts[0])
                cpu = float(parts[2])  # CPU is the 3rd column
                cpu_data[t].append(cpu)
            except ValueError:
                # Skip lines that don't have valid numbers
                continue

# Print the results
print("Time (m) | Avg CPU (Millicores) | Avg CPU (%) | Readings")
print("-" * 60)

# Also prepare CSV formatted output
csv_output = ["Time,Avg_CPU_Percentage"]

for t in sorted(cpu_data.keys()):
    values = cpu_data[t]
    avg_cpu_millicores = sum(values) / len(values)
    avg_cpu_percent = avg_cpu_millicores / 160  # Divide by 160 to get percentage
    print(f"{t:8} | {avg_cpu_millicores:20.2f} | {avg_cpu_percent:10.2f}% | {len(values)}")
    csv_output.append(f"{t},{avg_cpu_percent:.2f}")

print("\n--- CSV FORMAT (Easy to copy-paste for graphing) ---")
print("\n".join(csv_output))
