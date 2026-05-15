import csv
from collections import defaultdict
import os

# Path to the CSV file
filename = 'validation/k3s_sample.csv'

# Dictionary to store a list of RPS values for each time step (t)
rps_data = defaultdict(list)

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
        if len(parts) >= 2:
            try:
                t = int(parts[0])
                rps = float(parts[1])
                rps_data[t].append(rps)
            except ValueError:
                # Skip lines that don't have valid numbers
                continue

# Print the results
print("Time (m) | Average RPS | Number of Readings Averaged")
print("-" * 55)

# Also prepare CSV formatted output
csv_output = ["Time,Avg_RPS"]

for t in sorted(rps_data.keys()):
    values = rps_data[t]
    avg_rps = sum(values) / len(values)
    print(f"{t:8} | {avg_rps:11.2f} | {len(values)}")
    csv_output.append(f"{t},{avg_rps:.2f}")

print("\n--- CSV FORMAT (Easy to copy-paste for graphing) ---")
print("\n".join(csv_output))
