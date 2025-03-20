# Scripts for provisioning a very simple VMSS based cluster sans scheduler.

## Description

The motivation for this project is to provide a very simple way to quickly provision a VMSS cluster comprised of GPU VMs for testing purposes.

The main script `provision-cluster.sh` takes a configuration file as an argument and does the following:

- Provisions a VMSS
- Creates a public IP for the first VM in the VMSS which will act as a headnode
- Gathers the hostnames for all nodes in a `hostfile` and copies it to the headnode
- Creates a ssh keypair on the headnode and adds the public key to all nodes in the cluster
- Creates a second hostfile `hostfile-ip` consisting of the private IPs of each node and copies it to the headnode

The allocated VMs can use the example `cloud-init.yaml` file to prepare the VMs for use in the cluster.  The cloud-init is does the following:

- Installs some additional packages
- Prepares the NVMe disks as a RAID-0 at `/mnt/resource_nvme/`
- Configures Docker and Hugging Face to use the RAID-0
- Adds a script `/opt/node-info.sh` that populates `/var/log/node-info.log` with the VM's hostname, physical hostname, and private ip
    - Runs once during provisioning
- Adds a script `/opt/run-aznhc.sh` that will run [AzNHC](https://github.com/Azure/azurehpc-health-checks) and log results
  - Runs once during provisioning, can be rerun whenever
  - Test results logged to `/var/log/aznhc-health.log` and status logged to `/var/log/aznhc-health.log.status`
- Adds a script `/opt/run-dcgmi.sh` that will run [DCGM diagnostics](https://docs.nvidia.com/datacenter/dcgm/latest/user-guide/dcgm-diagnostics.html) and log results
  - Runs once during provisioning at level 2, can be rerun whenever at user specified level e.g. `/opt/run-dcgmi.sh 4`
  - Test results logged to `/var/log/dcgmi-diag.log` and status logged to `/var/log/dcgmi-diag.log.status`
- Adds a script `/opt/check-node-health.sh` that checks AzNHC and DCGMI logs to assess health based on last test results
  - Test results logged to `/var/log/node-health.log` and status logged to `/var/log/node-health.log.status`
- Adds a script `/opt/run-health-checks.sh` that runs AzNHC and DCGMI
- Sets GPUs on persistence mode (`nvidia-smi -pm 1`)on every reboot

## Scripts for cluster management

1. Script to update the hostfiles if VMs change (`update-hosts.sh`)
2. Script to run NCCCL tests (`run-nccl-test.sh`)
2. Script to aggregate files from nodes across the cluster all nodes (`gather-host-info.sh`)

## Provisioning steps

- 1. Create a `cluster-config.env` from `example-config.env`
- 2. Use `cluster-config.env` as the argument to `provision-cluster.sh`, i.e. `provision-cluster.sh cluster-config.env`
- 3. Log into the headnode using the public ip `ssh user@headnode-public-ip`
    - SSH is also available through public load balancer `ssh -p 50000 user@lb-public-ip`, but we assume connections will go through headnode NIC.
- 4. Check node health across cluster after all VMs have successfully provisioned, from headnode:
    - e.g. `bash /opt/gather-file.sh hostfile /var/log/node-health.log.status cluster-health.status`
    - Review cluster-health.status for unhealthy nodes and remediate, if necessary
- 5. Run NCCL all-reduce benchmark from headnode `run-nccl-test.sh hostfile`

## Assumptions

- Connections to headnode assumed to happen via SSH through the public IP attached the headnode NIC.
    - This could also happen through the load balancer, but would require adjusting the scripts to specify the load balancer's public IP and to specify the port where appropriate.