"""
K3s + OpenFaaS Multi-Node Profile — CloudLab
=============================================
Replicates the paper: "Kubernetes Distributions Performance on CloudLab with OpenFaaS"

Topology:
  - 1 Master node  : Runs K3s server + OpenFaaS gateway + factorial function
  - 2 Worker nodes : Join the K3s cluster as agents

Execution order (automated):
  1. Master: setup_master.sh  →  writes token + IP to /tmp/k3s_join_ready
  2. Workers: poll master's /tmp/ via SSH-less shared signal, then join

NOTE: collect_token.sh and verify_cluster.sh are meant to be run
      manually from the master after the experiment is instantiated.
"""

import geni.portal as portal
import geni.rspec.pg as rspec
import geni.rspec.igext as igext

# ── Portal parameters (shown to user at experiment creation) ──
pc = portal.Context()

pc.defineParameter(
    "num_workers",
    "Number of Worker Nodes",
    portal.ParameterType.INTEGER,
    2,
    longDescription="How many K3s worker nodes to create (1–4 recommended)."
)

pc.defineParameter(
    "node_type",
    "Hardware Node Type",
    portal.ParameterType.NODETYPE,
    "c220g2",
    longDescription="CloudLab hardware type. c220g2 (Wisconsin) is recommended: "
                    "10-core Xeon, 160 GB RAM. Use 'pc3000' at Emulab or "
                    "'d430' at Apt cluster."
)

params = pc.bindParameters()

# ── Validate ──
if params.num_workers < 1 or params.num_workers > 4:
    pc.reportError(portal.ParameterError(
        "num_workers must be between 1 and 4.", ["num_workers"]
    ))
pc.verifyParameters()

# ── Build RSpec ──
request = pc.makeRequestRSpec()

# Shared LAN for all nodes
lan = request.LAN("k3s-lan")
lan.best_effort = True
lan.vlan_tagging = True

# ── Helper: create a node and attach to LAN ──
def make_node(name, startup_cmd):
    node = request.RawPC(name)
    node.hardware_type = params.node_type
    node.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"
    iface = node.addInterface("if-" + name)
    iface.addAddress(rspec.IPv4Address("192.168.1." + str(10 + list_nodes.index(name)), "255.255.255.0"))
    lan.addInterface(iface)
    node.addService(rspec.Execute(shell="bash", command=startup_cmd))
    return node

# ── Track node names for IP assignment ──
list_nodes = ["master"] + ["worker" + str(i) for i in range(params.num_workers)]

# ── MASTER NODE ──
master = request.RawPC("master")
master.hardware_type = params.node_type
master.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"

master_iface = master.addInterface("if-master")
lan.addInterface(master_iface)

master.addService(rspec.Execute(
    shell="bash",
    command=(
        "sudo bash /local/repository/multi-node/setup_master.sh "
        "> /tmp/setup_master.log 2>&1 ; "
        # After master setup, write join info to a shared file workers can poll
        "sudo cat /var/lib/rancher/k3s/server/node-token > /tmp/k3s_token ; "
        "hostname -I | awk '{print $1}' > /tmp/master_ip ; "
        "touch /tmp/k3s_master_ready"
    )
))

# ── WORKER NODES ──
for i in range(params.num_workers):
    worker = request.RawPC("worker" + str(i))
    worker.hardware_type = params.node_type
    worker.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"

    worker_iface = worker.addInterface("if-worker" + str(i))
    lan.addInterface(worker_iface)

    # Workers poll the master node until setup_master.sh is done,
    # then read the token and IP via SSH (CloudLab sets up passwordless SSH
    # between all nodes in an experiment automatically).
    worker.addService(rspec.Execute(
        shell="bash",
        command=(
            # Wait for master to finish (up to 20 min)
            "echo 'Waiting for master to be ready...' ; "
            "for i in $(seq 1 120); do "
            "  ssh -o StrictHostKeyChecking=no master 'test -f /tmp/k3s_master_ready' "
            "  && break ; "
            "  sleep 10 ; "
            "done ; "
            # Fetch token and master IP from master node
            "MASTER_IP=$(ssh -o StrictHostKeyChecking=no master 'cat /tmp/master_ip') ; "
            "K3S_TOKEN=$(ssh -o StrictHostKeyChecking=no master 'cat /tmp/k3s_token') ; "
            "echo \"Master IP: $MASTER_IP, Token: $K3S_TOKEN\" ; "
            # Run worker setup with those arguments
            "sudo bash /local/repository/multi-node/setup_worker.sh "
            "\"$MASTER_IP\" \"$K3S_TOKEN\" "
            "> /tmp/setup_worker.log 2>&1"
        )
    ))

# ── Profile metadata (shown on CloudLab profile page) ──
profile_description = igext.AddProfileParameters(request)

pc.printRequestRSpec(request)
