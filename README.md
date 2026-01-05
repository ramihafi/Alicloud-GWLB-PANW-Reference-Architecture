# Alibaba Cloud GWLB with Palo Alto VM-Series – Reference Architecture

This repository provides a **production-grade reference architecture** for deploying **Palo Alto Networks VM-Series firewalls** behind **Alibaba Cloud Gateway Load Balancer (GWLB)** using **CEN Transit Router**, **PrivateLink GWLB Endpoints**, and **Terraform**.

The design supports:
- East-West traffic inspection
- Outbound (Internet) inspection
- Inbound traffic inspection using **Public ALB**
- High availability across **multiple AZs**
- Firewall failover with GWLB symmetry

---

## Architecture Overview

This architecture uses:
- **Security VPC** with GWLB + VM-Series firewalls
- **App1 and App2 VPCs** as spokes
- **CEN Transit Router** for hub-and-spoke routing
- **PrivateLink Gateway Load Balancer Endpoints (GWLBe)**
- **NAT Gateway** for outbound Internet access
- **Public Application Load Balancer (ALB)** for inbound traffic

All routing logic is intentionally explicit to demonstrate **real-world GWLB behavior** in Alibaba Cloud.

---

## Architecture Diagram

![GWLB Architecture](Rami-Alicloud-Lab%20-%20GWLB%20wth%20RT.png)

---

## Prerequisites

Before you begin, ensure you have:

- Alibaba Cloud account with sufficient permissions
- Terraform ≥ 1.4
- Alibaba Cloud Terraform provider
- VM-Series image available in your region
- SSH key pair created
- Basic familiarity with:
  - VPC routing
  - Palo Alto VM-Series
  - GWLB concepts

---

## Deployment Flow (High Level)

1. Deploy infrastructure using Terraform
2. License and prepare firewalls
3. Enable GENEVE inspection
4. Configure firewall interfaces and policies
5. Validate outbound and East-West traffic
6. Enable inbound traffic using Public ALB
7. Validate full traffic flow

---

## Step-by-Step Guide

---

1️⃣ Apply Terraform

```bash
terraform init
terraform apply



Terraform deploys:
	•	VPCs and subnets
	•	GWLB and GWLB endpoints
	•	CEN Transit Router and attachments
	•	NAT Gateways with SNAT
	•	ALBs and backend server groups
	•	Route tables (where supported)

⚠️ Some system routes cannot be modified via Terraform and must be handled manually (explained later).

⸻

2️⃣ License, Update, and Upgrade Firewalls

Minimum required versions:
	•	PAN-OS: 12.1.2 or higher
	•	VM-Series Plugin: 6.1.0 or higher

Steps:
	1.	Assign licenses
	2.	Upgrade PAN-OS
	3.	Upgrade VM-Series plugin
	4.	Reboot if required

⸻

3️⃣ Disable DPDK (Mandatory)

GWLB requires GENEVE, which is not compatible with DPDK.

On each firewall:

set system setting dpdk-pkt-io off
commit

4️⃣ Enable GENEVE Inspection

request plugins vm_series geneve-inspect enable yes

Confirm status:

show plugins vm_series

5️⃣ Configure Firewall Interfaces

Configure the GWLB-connected interface (example: ethernet1/1):
	•	Type: Layer3
	•	IP assignment: DHCP
	•	Zone: untrust
	•	Interface management: Allow All

CLI example:

set network interface ethernet ethernet1/1 layer3 dhcp-client enable yes
set network interface ethernet ethernet1/1 layer3 interface-management-profile allow-all
set zone untrust network layer3 ethernet1/1
commit

6️⃣ Configure Security Policies

Create two rules:

a) allow-probe
	•	Source: GWLB IPs
	•	Destination: any
	•	Action: allow
	•	Logging: disabled

b) allow-all
	•	Source: any
	•	Destination: any
	•	Action: allow
	•	Logging: enabled (optional)

Order matters: allow-probe must be first.

⸻

7️⃣ Adjust Interface MTU (Critical)

GENEVE adds 64–68 bytes of overhead.

Effective MTU calculation:

1500 (VPC MTU) - 64 (GENEVE) ≈ 1436

Set MTU slightly lower for safety:

set network interface ethernet ethernet1/1 layer3 mtu 1432
commit


⸻

8️⃣ Validate Outbound & East-West Traffic

At this point:
	•	App1 ↔ App2 traffic should work
	•	Outbound Internet access should work
	•	Traffic should be visible on firewalls

⸻

9️⃣ Enable Web Service on App1 and App2

Run on both servers:

sudo apt update
sudo apt install -y apache2
sudo systemctl enable apache2
sudo systemctl start apache2
sudo ufw allow 80/tcp
sudo ufw reload

Create test pages:

App1

echo "<h1>App1 - Inbound OK</h1>" | sudo tee /var/www/html/index.html

App2

echo "<h1>App2 - Inbound OK</h1>" | sudo tee /var/www/html/index.html

Test East-West:

curl http://<APP1_PRIVATE_IP>
curl http://<APP2_PRIVATE_IP>

🔟 Inbound Traffic Enablement (Important)

Inbound traffic cannot be fully automated due to Alibaba Cloud limitations around system and gateway route tables.

Why This Is Manual
	•	IPv4 Gateway route tables have restricted route types
	•	Some system routes cannot be modified via Terraform
	•	GWLB Endpoint routes are treated as special gateway routes

This is expected behavior and not a Terraform issue.

⸻

Inbound Design

Inbound flow:

Internet
 → Public ALB
 → GWLB Endpoint (App VPC)
 → Firewalls (Security VPC)
 → App Server

 Manual Step Required (Critical)

For each App VPC, you must manually add routes in the Gateway Route Table:

Example (App1)

Destination          Next Hop
10.20.4.0/24         GWLBe App1-B
10.20.14.0/24        GWLBe App1-C

How to Do It:
	1.	Go to VPC → Route Tables
	2.	Select Gateway Route Table
	3.	Add Custom Route
	4.	Choose Gateway Load Balancer Endpoint as next hop
	5.	Save

Repeat for App2.

⸻

Why ALB Is Used
	•	Internet-facing ALB handles:
	•	EIP
	•	Listener
	•	Health checks
	•	Backend servers remain private
	•	Firewalls inspect both inbound and outbound traffic

⸻

Testing Inbound Traffic

After configuration:

http://<ALB_PUBLIC_IP>

Expected result:
	•	App1 shows “Inbound OK”
	•	App2 shows “Inbound OK”
	•	Firewall logs confirm inspection

⸻

Known Limitations & Notes
	•	Some GWLB system routes cannot be managed by Terraform
	•	Gateway Route Tables are more restrictive than VSwitch RTs
	•	This behavior matches Alibaba Cloud console behavior
	•	Design intentionally mirrors real customer deployments

⸻

Cleanup

To destroy resources:

terraform destroy

⚠️ Manually added gateway routes must be removed before destroy.

⸻

Final Notes

This lab is designed to:
	•	Be educational
	•	Be realistic
	•	Reflect actual Alibaba Cloud + PANW constraints

If you understand this architecture, you understand GWLB on Alibaba Cloud.

⸻

Author: Rami Hafi
Purpose: Reference Architecture / Field Enablement
Status: Fully Functional & Validated

