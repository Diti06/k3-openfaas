# encoding: utf-8
import geni.portal as portal
import geni.rspec.pg as rspec

pc = portal.Context()

pc.defineParameter(
    "num_workers",
    "Number of Worker Nodes",
    portal.ParameterType.INTEGER,
    2,
    longDescription="Number of K3s worker nodes to create (1 to 4)."
)

pc.defineParameter(
    "node_type",
    "Hardware Node Type",
    portal.ParameterType.NODETYPE,
    "c220g2",
    longDescription="CloudLab hardware type. c220g2 recommended."
)

params = pc.bindParameters()

if params.num_workers < 1 or params.num_workers > 4:
    pc.reportError(portal.ParameterError(
        "num_workers must be between 1 and 4.", ["num_workers"]
    ))

pc.verifyParameters()

request = pc.makeRequestRSpec()

# Shared LAN
lan = request.LAN("k3s-lan")
lan.best_effort = True
lan.vlan_tagging = True

# Master node
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
        "sudo cat /var/lib/rancher/k3s/server/node-token > /tmp/k3s_token ; "
        "hostname -I | awk '{print $1}' > /tmp/master_ip ; "
        "touch /tmp/k3s_master_ready"
    )
))

# Worker nodes
for i in range(params.num_workers):
    worker = request.RawPC("worker" + str(i))
    worker.hardware_type = params.node_type
    worker.disk_image = "urn:publicid:IDN+emulab.net+image+emulab-ops:UBUNTU22-64-STD"
    worker_iface = worker.addInterface("if-worker" + str(i))
    lan.addInterface(worker_iface)

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

pc.printRequestRSpec(request)
