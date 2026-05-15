import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
import os

# Ensure the file exists before reading
csv_path = 'validation/cpu_avg.csv'
if not os.path.exists(csv_path):
    print(f"Error: Could not find {csv_path}")
    exit(1)

# Read the averaged CPU data
df = pd.read_csv(csv_path)

# Create the plot
plt.figure(figsize=(10, 5))

# Plotting Time on X-axis and CPU on Y-axis
# Using a green square marker ('s') to perfectly mimic the K3s line in the paper
plt.plot(df['Time'], df['Avg_CPU_Percentage'], marker='s', color='#00b050', linewidth=2, label='K3s', markersize=8)

# Formatting the graph
plt.xlabel('Time (m)', fontsize=12)
plt.ylabel('CPU Usage (Percentage)', fontsize=12)

# Set the X-axis intervals to 0, 2, 4, 6... 30
plt.xticks(np.arange(0, 33, 2))

# Set the Y-axis intervals to 0, 20, 40... 100 as requested
plt.yticks(np.arange(0, 101, 20))
plt.ylim(0, 100) # Give it a clean cap at 100%

# Add horizontal grid lines like the paper
plt.grid(axis='y', linestyle='-', alpha=0.5)

# Add the legend at the top
plt.legend(loc='upper center', bbox_to_anchor=(0.5, 1.15), ncol=4, frameon=False, prop={'weight':'bold'})

# Save the graph as an image
output_file = 'validation/k3s_cpu_graph.png'
plt.tight_layout()
plt.savefig(output_file, dpi=300)
print(f"Success! CPU Graph has been beautifully plotted and saved as: {output_file}")
