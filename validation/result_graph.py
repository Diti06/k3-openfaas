import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

# 1. Read the CSV file
# Make sure k3s_sample.csv is in the same folder as this script
df = pd.read_csv("k3s_sample.csv")

# Optional: print to verify
print(df.head())

# 2. Plot RPS vs time (minutes)
plt.figure(figsize=(8, 4))
plt.plot(df["t"], df["RPS"], marker="o", color="tab:orange")
plt.xlabel("Time (minutes)")
plt.ylabel("RPS")
plt.title("RPS vs Time (k3s)")
plt.grid(True)
plt.xticks(np.arange(0, df["t"].max() + 2, 2))
plt.tight_layout()
plt.savefig("rps_vs_time_k3s.png")  # or use plt.show()

# 3. Plot CPU usage vs time (minutes)
plt.figure(figsize=(8, 4))
plt.plot(df["t"], df["CPU"], marker="o", color="tab:blue")
plt.xlabel("Time (minutes)")
plt.ylabel("CPU usage")
plt.title("CPU Usage vs Time (k3s)")
plt.grid(True)
plt.tight_layout()
plt.savefig("cpu_vs_time_k3s.png")  # or use plt.show()

print("Saved rps_vs_time_k3s.png and cpu_vs_time_k3s.png")