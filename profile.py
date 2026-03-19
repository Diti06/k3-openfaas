# encoding: utf-8
import geni.portal as portal
import geni.rspec.pg as rspec

pc = portal.Context()

pc.defineParameter(
    "node_type",
    "Hardware Node Type",
    portal.ParameterType.NODETYPE,
    "c220g2",
    longDescription="CloudLab hardware type. c220g2 recommended."
)

params = pc.bindParameters()
pc.verifyParameters()

request = pc.makeRequestRSpec()

# -------------------------------------------------------
# LAN 1: Cluster LAN — Master + 3 Workers
# This is the internal K3s cluster network
# -------------------------------------------------------
cluster_lan = request.LAN("cluster-lan")
cluster_lan.best_effort = True
cluster_lan.vlan_tagging = True

# -------------------------------------------------------
# LAN 2: API LAN — Master + Measurement Node
# Measurement node sends load via OpenFaaS gateway API
# -------------------------------------------------------
api_lan = request.LAN("api-lan")
api_lan.best_effort = True
api_lan.vlan_tagging = True

# -------------------------------------------------------
# MASTER NODE
# - Runs K3s server
# - Runs OpenFaaS gateway (port 31112)
# - Connected to BOTH cluster-lan and api-lan
# -------------------------------------------------------
master = request.RawPC("master")
master.hardware_type = params.node_type
master.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"

# Master connects to cluster LAN (for workers)
master_cluster_iface = master.addInterface("if-master-cluster")
cluster_lan.addInterface(master_cluster_iface)

# Master also connects to API LAN (for measurement node)
master_api_iface = master.addInterface("if-master-api")
api_lan.addInterface(master_api_iface)

master.addService(rspec.Execute(
    shell="bash",
    command=(
        "sudo bash /local/repository/multi-node/setup_master.sh "
        "> /tmp/setup_master.log 2>&1 ; "
        "sudo cat /var/lib/rancher/k3s/server/node-token > /tmp/k3s_token ; "
        "hostname -I | awk '{print $1}' > /tmp/master_ip ; "
        "touch /tmp/k3s_master_ready"
    )
))

# -------------------------------------------------------
# WORKER NODES (3) — Join K3s cluster via cluster-lan
# Run OpenFaaS function pods (factorial)
# -------------------------------------------------------
for i in range(3):
    worker = request.RawPC("worker" + str(i))
    worker.hardware_type = params.node_type
    worker.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"

    worker_iface = worker.addInterface("if-worker" + str(i))
    cluster_lan.addInterface(worker_iface)

    worker.addService(rspec.Execute(
        shell="bash",
        command=(
            "for i in $(seq 1 120); do "
            "  ssh -o StrictHostKeyChecking=no master "
            "  'test -f /tmp/k3s_master_ready' && break ; "
            "  sleep 10 ; "
            "done ; "
            "MASTER_IP=$(ssh -o StrictHostKeyChecking=no master 'cat /tmp/master_ip') ; "
            "K3S_TOKEN=$(ssh -o StrictHostKeyChecking=no master 'cat /tmp/k3s_token') ; "
            "sudo bash /local/repository/multi-node/setup_worker.sh "
            "\"$MASTER_IP\" \"$K3S_TOKEN\" "
            "> /tmp/setup_worker.log 2>&1"
        )
    ))

# -------------------------------------------------------
# MEASUREMENT NODE
# - NOT part of K3s cluster
# - Connects ONLY to api-lan
# - Runs k6 load tests against master's OpenFaaS gateway
# - Collects RPS, latency, scaling metrics
# -------------------------------------------------------
measurement = request.RawPC("measurement")
measurement.hardware_type = params.node_type
measurement.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"

meas_iface = measurement.addInterface("if-measurement-api")
api_lan.addInterface(meas_iface)

measurement.addService(rspec.Execute(
    shell="bash",
    command=(
        # Install k6 load testing tool
        "sudo gpg -k ; "
        "sudo gpg --no-default-keyring "
        "--keyring /usr/share/keyrings/k6-archive-keyring.gpg "
        "--keyserver hkp://keyserver.ubuntu.com:80 "
        "--recv-keys C5AD17C747E3415A3642D57D77C6C491D6AC1D69 ; "
        "echo 'deb [signed-by=/usr/share/keyrings/k6-archive-keyring.gpg] "
        "https://dl.k6.io/deb stable main' "
        "| sudo tee /etc/apt/sources.list.d/k6.list ; "
        "sudo apt-get update -qq && sudo apt-get install -y k6 ; "
        "echo 'Measurement node ready' > /tmp/measurement_ready"
    )
))

pc.printRequestRSpec(request)
