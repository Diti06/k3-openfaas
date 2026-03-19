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

# Cluster LAN: master + 3 workers (K3s internal network)
cluster_lan = request.LAN("cluster-lan")
cluster_lan.best_effort = True
cluster_lan.vlan_tagging = True

# API LAN: master + measurement node (load test network)
api_lan = request.LAN("api-lan")
api_lan.best_effort = True
api_lan.vlan_tagging = True

# Master node: K3s server + OpenFaaS gateway
# Connected to both LANs
master = request.RawPC("master")
master.hardware_type = params.node_type
master.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"
cluster_lan.addInterface(master.addInterface("if-master-cluster"))
api_lan.addInterface(master.addInterface("if-master-api"))
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

# Worker nodes: K3s agents, connected only to cluster LAN
for i in range(3):
    worker = request.RawPC("worker" + str(i))
    worker.hardware_type = params.node_type
    worker.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"
    cluster_lan.addInterface(worker.addInterface("if-worker" + str(i)))
    worker.addService(rspec.Execute(
        shell="bash",
        command=(
            "for i in $(seq 1 120); do "
            "ssh -o StrictHostKeyChecking=no master "
            "'test -f /tmp/k3s_master_ready' && break ; "
            "sleep 10 ; done ; "
            "MASTER_IP=$(ssh -o StrictHostKeyChecking=no master 'cat /tmp/master_ip') ; "
            "K3S_TOKEN=$(ssh -o StrictHostKeyChecking=no master 'cat /tmp/k3s_token') ; "
            "sudo bash /local/repository/multi-node/setup_worker.sh "
            "\"$MASTER_IP\" \"$K3S_TOKEN\" > /tmp/setup_worker.log 2>&1"
        )
    ))

# Measurement node: runs k6 load tests, connected only to API LAN
measurement = request.RawPC("measurement")
measurement.hardware_type = params.node_type
measurement.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"
api_lan.addInterface(measurement.addInterface("if-measurement"))
measurement.addService(rspec.Execute(
    shell="bash",
    command=(
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
