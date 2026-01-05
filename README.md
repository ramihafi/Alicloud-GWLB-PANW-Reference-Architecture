# Alicloud GWLB + TR Lab (rhafi-gwlb)

This Terraform project builds a full Alicloud lab for testing Gateway Load Balancer (GWLB) with Palo Alto VM-Series in a central **Security VPC**, and two spoke VPCs: **App1** and **App2**.

Terraform deploys:

- 1× Security VPC with:
  - Private vswitches for firewalls (AZ B/C)
  - Mgmt vswitches for firewalls (AZ B/C)
  - GWLB
  - GWLB endpoint in Security VPC (GWLBe-Sec)
  - NAT Gateway for firewall outbound / updates

- 2× App VPCs (App1, App2) with:
  - Instance vswitches (AZ B/C)
  - GWLBe vswitches (AZ B/C)
  - ALB vswitches (AZ B/C)
  - IGW vswitches (AZ B/C)
  - ALBs for inbound traffic
  - TR attachments to Security VPC

- CEN / Transit Router:
  - TR with attachments:
    - Security VPC (appliance mode enabled)
    - App1 VPC
    - App2 VPC
  - Inspection route table to steer east–west traffic via Security VPC

> ⚠️ **Important:** Alicloud does **not** allow us (via Terraform) to directly change some **system routes** in VPC route tables (e.g., VSwitch-local CIDRs).  
> However, the console lets you edit the **next hop** for those entries.  
> Because of that, a few routes must be added / adjusted manually.

---

## 1. Terraform Deployment

1. Configure your Alicloud credentials locally (environment variables or `aliyun configure`).
2. Adjust `terraform.tfvars` (if provided) for:
   - `region`
   - CIDRs
   - image IDs
   - key pair name
3. Run:

   ```bash
   terraform init
   terraform apply

   4.	Wait until the deployment completes successfully.

At this point, all core resources (VPCs, vswitches, GWLB, GWLBe, TR, NAT GW, ALBs, ECS instances, etc.) are created.

⸻

2. Manual Route Updates (App1 – Inbound Flow)

For App1 inbound inspection, we want this logical path:
	•	Internet → IGW → GWLBe-App1 → GWLB → Firewalls (Security VPC) → GWLBe-App1 → ALB → App1 instances

To achieve this in Alicloud, we must edit some routes in the App1 VPC using the console, because they are system routes and Terraform cannot modify them.

2.1. Prerequisites (find IDs / names)

From the Alicloud console, or from Terraform outputs/state, identify:
	•	App1 VPC: rhafi-gwlb-app1-vpc (or equivalent)
	•	App1 GWLBe endpoint:
	•	Name should look like: rhafi-gwlb-app1-gwlbe
	•	Type: GatewayLoadBalancer
	•	ID will look like: ep-xxxxxxxxxxxxxxxxxxxx
	•	App1 route tables:
	•	app1-igw-rt – attached to the App1 IGW vswitches
	•	app1-alb-rt – attached to the App1 ALB vswitches
	•	app1-gwlbe-rt – attached to the App1 GWLBe vswitches
	•	app1-instances-rt – attached to the App1 instance vswitches

Names are created by Terraform using a system_prefix like rhafi-gwlb-, e.g. rhafi-gwlb-app1-igw-rt, etc.

⸻

2.2. Edit IGW Route Table (app1-igw-rt)

Goal:
	•	For traffic coming from the internet to App1 workloads in subnets:
	•	10.20.4.0/24
	•	10.20.14.0/24
	•	We want IGW-side RT to send that traffic to GWLBe-App1.

Steps:
	1.	Go to VPC Console → Route Tables.
	2.	Filter by App1 VPC and find the route table named (or tagged) like:
	•	app1-igw-rt (Terraform-created)
	3.	Open the Routes tab.
	4.	Locate the system routes for:
	•	10.20.4.0/24
	•	10.20.14.0/24
	5.	For each of these two routes:
	•	Click Edit (Modify Route Entry).
	•	Change Next Hop Type to: GatewayEndpoint
	•	Select Next Hop: GWLBe-App1 (ep-xxxxxxxxxxxxxxxxxxxx)
	•	Save.

After this, the IGW route table should have:

Destination.     Next Hop Type.      Next Hop
10.20.4.0/24.    GatewayEndpoint.    GWLBe-App1 (ep-*)
10.20.14.0/24.   GatewayEndpoint.    GWLBe-App1 (ep-*)


2.3. Edit ALB Route Table (app1-alb-rt)

Goal:
	•	For traffic from ALBs to the internet, we want ALB subnets to send all non-local traffic to GWLBe-App1, so it gets inspected by the firewalls.

Steps:
	1.	In VPC Console → Route Tables, locate:
	•	app1-alb-rt (attached to App1 ALB vswitches)
	2.	Open Routes.
	3.	Find the default route:
	•	0.0.0.0/0
	4.	Edit that route:
	•	Set Next Hop Type = GatewayEndpoint
	•	Next Hop = GWLBe-App1 (ep-xxxxxxxxxxxxxxxxxxxx)
	•	Save.

Result:

Destination.     Next Hop Type.    Next Hop
0.0.0.0/0.       GatewayEndpoint.  GWLBe-App1 (ep-*)


This ensures ALB → Internet traffic is steered through GWLB → firewalls.

⸻

2.4. GWLBe Route Table (app1-gwlbe-rt)

Terraform already attaches the route table for GWLBe vswitches and configures default routes (for example to IGW or NAT, depending on the current design).

You typically want:
	•	0.0.0.0/0 → IGW (or NAT, depending on whether the return path should be public or private)

Verify in the console that:
	1.	Route table app1-gwlbe-rt is attached to the GWLBe vswitches.
	2.	It has a default route that sends traffic out to the correct next hop (IGW or NAT GW).

⸻

2.5. Instance Route Table (app1-instances-rt)

Terraform configures App1 instance subnets to send:
	•	0.0.0.0/0 → Transit Router Attachment (Attachment)

So that east–west and outbound traffic is steered into the TR → Security VPC → GWLB → FW path.

No manual change is required here unless you want to adjust additional prefixes.

⸻

3. Re-running Terraform

After these manual steps, you can safely re-run:

terraform plan
terraform apply


Terraform will:
	•	Manage all infrastructure (VPCs, vswitches, TR, attachments, GWLB/GWLBe, ALBs, NAT GWs, ECS, etc.).
	•	Not touch the manual system route changes you made in the console.

As long as we do not reintroduce those 3 alicloud_route_entry resources in Terraform, future applies will leave these console-edited routes alone.

⸻

4. Notes for Colleagues
	•	If you destroy the stack (terraform destroy) the manual routes will vanish with the VPC.
	•	If you recreate from scratch, repeat the manual steps in this README after terraform apply.
	•	For App2, you can mirror the same pattern:
	•	Create the equivalent IGW and ALB route tables (app2-igw-rt, app2-alb-rt) via Terraform.
	•	Manually change their system/default routes to point to GWLBe-App2 endpoints in the console.