############################################
# main.tf
############################################

terraform {
  required_providers {
    alicloud = {
      source  = "aliyun/alicloud"
      version = "~> 1.267.0"
    }
  }
}

provider "alicloud" {
  region = var.region
}

########################
# Resource Group (optional) + locals
########################

data "alicloud_resource_manager_resource_groups" "rg" {
  count      = var.resource_group_name_regex == "" ? 0 : 1
  name_regex = var.resource_group_name_regex
}

locals {
  target_rg_id  = var.resource_group_name_regex == "" ? null : data.alicloud_resource_manager_resource_groups.rg[0].groups[0].id
  system_prefix = var.system_prefix
  system_name   = "${var.system_prefix}-tr"
}

########################
# 1. VPCs
########################

resource "alicloud_vpc" "sec" {
  vpc_name   = "${local.system_prefix}-security-vpc"
  cidr_block = var.cidr_security
}

resource "alicloud_vpc" "app1" {
  vpc_name   = "${local.system_prefix}-app1-vpc"
  cidr_block = var.cidr_app1
}

resource "alicloud_vpc" "app2" {
  vpc_name   = "${local.system_prefix}-app2-vpc"
  cidr_block = var.cidr_app2
}

########################
# 2. VSwitches – Security VPC
########################

# FW private subnets (AZ B / AZ C)
resource "alicloud_vswitch" "sec_fw1_private" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.3.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-sec-fw1-private-zone-b"
}

resource "alicloud_vswitch" "sec_fw2_private" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.13.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-sec-fw2-private-zone-c"
}

# GWLBe subnets (AZ B / AZ C)
resource "alicloud_vswitch" "sec_gwlb_b" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.2.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-sec-gwlb-b"
}

resource "alicloud_vswitch" "sec_gwlb_c" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.12.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-sec-gwlb-c"
}

# FW mgmt subnets (AZ B / AZ C)
resource "alicloud_vswitch" "sec_fw1_mgmt" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.5.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-sec-fw1-mgmt-zone-b"
}

resource "alicloud_vswitch" "sec_fw2_mgmt" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.15.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-sec-fw2-mgmt-zone-c"
}

# NATGW subnets (AZ B / AZ C)
resource "alicloud_vswitch" "sec_nat_b" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.4.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-sec-nat-b"
}

resource "alicloud_vswitch" "sec_nat_c" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.14.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-sec-nat-c"
}

# VPC attachment subnets (AZ B / AZ C)
resource "alicloud_vswitch" "sec_att_b" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.1.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-sec-vpc-att-b"
}

resource "alicloud_vswitch" "sec_att_c" {
  vpc_id       = alicloud_vpc.sec.id
  cidr_block   = "10.10.11.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-sec-vpc-att-c"
}

########################
# 2.1 NAT Gateways – Security VPC (Zone B & Zone C)
########################

resource "alicloud_nat_gateway" "sec_nat_b" {
  vpc_id           = alicloud_vpc.sec.id
  nat_gateway_name = "${local.system_prefix}-sec-natgw-b"
  nat_type         = "Enhanced"
  payment_type     = "PayAsYouGo"
  vswitch_id       = alicloud_vswitch.sec_nat_b.id
}

resource "alicloud_nat_gateway" "sec_nat_c" {
  vpc_id           = alicloud_vpc.sec.id
  nat_gateway_name = "${local.system_prefix}-sec-natgw-c"
  nat_type         = "Enhanced"
  payment_type     = "PayAsYouGo"
  vswitch_id       = alicloud_vswitch.sec_nat_c.id
}

resource "alicloud_eip_address" "sec_nat_b_eip" {
  address_name = "${local.system_prefix}-sec-nat-b-eip"
  bandwidth    = "10"
  isp          = "BGP"
}

resource "alicloud_eip_association" "sec_nat_b_eip_assoc" {
  allocation_id = alicloud_eip_address.sec_nat_b_eip.id
  instance_id   = alicloud_nat_gateway.sec_nat_b.id
}

resource "alicloud_eip_address" "sec_nat_c_eip" {
  address_name = "${local.system_prefix}-sec-nat-c-eip"
  bandwidth    = "10"
  isp          = "BGP"
}

resource "alicloud_eip_association" "sec_nat_c_eip_assoc" {
  allocation_id = alicloud_eip_address.sec_nat_c_eip.id
  instance_id   = alicloud_nat_gateway.sec_nat_c.id
}

resource "alicloud_snat_entry" "sec_nat_b_snat_10_8" {
  snat_table_id = alicloud_nat_gateway.sec_nat_b.snat_table_ids
  source_cidr   = "10.0.0.0/8"
  snat_ip       = alicloud_eip_address.sec_nat_b_eip.ip_address

  depends_on = [alicloud_eip_association.sec_nat_b_eip_assoc]
}

resource "alicloud_snat_entry" "sec_nat_c_snat_10_8" {
  snat_table_id = alicloud_nat_gateway.sec_nat_c.snat_table_ids
  source_cidr   = "10.0.0.0/8"
  snat_ip       = alicloud_eip_address.sec_nat_c_eip.ip_address

  depends_on = [alicloud_eip_association.sec_nat_c_eip_assoc]
}

########################
# 3. VSwitches – App1 VPC
########################

resource "alicloud_vswitch" "app1_inst_b" {
  vpc_id       = alicloud_vpc.app1.id
  cidr_block   = "10.20.4.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-app1-inst-b"
}

resource "alicloud_vswitch" "app1_inst_c" {
  vpc_id       = alicloud_vpc.app1.id
  cidr_block   = "10.20.14.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-app1-inst-c"
}

resource "alicloud_vswitch" "app1_gwlb_b" {
  vpc_id       = alicloud_vpc.app1.id
  cidr_block   = "10.20.3.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-app1-gwlb-b"
}

resource "alicloud_vswitch" "app1_gwlb_c" {
  vpc_id       = alicloud_vpc.app1.id
  cidr_block   = "10.20.13.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-app1-gwlb-c"
}

resource "alicloud_vswitch" "app1_alb_b" {
  vpc_id       = alicloud_vpc.app1.id
  cidr_block   = "10.20.2.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-app1-alb-b"
}

resource "alicloud_vswitch" "app1_alb_c" {
  vpc_id       = alicloud_vpc.app1.id
  cidr_block   = "10.20.12.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-app1-alb-c"
}

resource "alicloud_vswitch" "app1_igw_b" {
  vpc_id       = alicloud_vpc.app1.id
  cidr_block   = "10.20.1.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-app1-igw-b"
}

resource "alicloud_vswitch" "app1_igw_c" {
  vpc_id       = alicloud_vpc.app1.id
  cidr_block   = "10.20.11.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-app1-igw-c"
}

########################
# 4. VSwitches – App2 VPC
########################

resource "alicloud_vswitch" "app2_inst_b" {
  vpc_id       = alicloud_vpc.app2.id
  cidr_block   = "10.30.4.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-app2-inst-b"
}

resource "alicloud_vswitch" "app2_inst_c" {
  vpc_id       = alicloud_vpc.app2.id
  cidr_block   = "10.30.14.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-app2-inst-c"
}

resource "alicloud_vswitch" "app2_gwlb_b" {
  vpc_id       = alicloud_vpc.app2.id
  cidr_block   = "10.30.3.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-app2-gwlb-b"
}

resource "alicloud_vswitch" "app2_gwlb_c" {
  vpc_id       = alicloud_vpc.app2.id
  cidr_block   = "10.30.13.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-app2-gwlb-c"
}

resource "alicloud_vswitch" "app2_alb_b" {
  vpc_id       = alicloud_vpc.app2.id
  cidr_block   = "10.30.2.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-app2-alb-b"
}

resource "alicloud_vswitch" "app2_alb_c" {
  vpc_id       = alicloud_vpc.app2.id
  cidr_block   = "10.30.12.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-app2-alb-c"
}

resource "alicloud_vswitch" "app2_igw_b" {
  vpc_id       = alicloud_vpc.app2.id
  cidr_block   = "10.30.1.0/24"
  zone_id      = var.az_b
  vswitch_name = "${local.system_prefix}-app2-igw-b"
}

resource "alicloud_vswitch" "app2_igw_c" {
  vpc_id       = alicloud_vpc.app2.id
  cidr_block   = "10.30.11.0/24"
  zone_id      = var.az_c
  vswitch_name = "${local.system_prefix}-app2-igw-c"
}

########################
# 5. CEN + Transit Router + Attachments
########################

resource "alicloud_cen_instance" "cen" {
  cen_instance_name = "${local.system_name}-cen"
  description       = "CEN for ${local.system_name}"

  # remove if you don’t want RG dependency
  resource_group_id = local.target_rg_id
}

resource "alicloud_cen_transit_router" "tr" {
  cen_id              = alicloud_cen_instance.cen.id
  transit_router_name = "${local.system_name}-tr"
}

resource "alicloud_cen_transit_router_vpc_attachment" "att_security" {
  cen_id            = alicloud_cen_instance.cen.id
  transit_router_id = alicloud_cen_transit_router.tr.transit_router_id
  vpc_id            = alicloud_vpc.sec.id

  transit_router_vpc_attachment_name = "${local.system_prefix}-att-security"
  auto_publish_route_enabled         = false

  zone_mappings {
    vswitch_id = alicloud_vswitch.sec_att_b.id
    zone_id    = var.az_b
  }

  zone_mappings {
    vswitch_id = alicloud_vswitch.sec_att_c.id
    zone_id    = var.az_c
  }

  transit_router_vpc_attachment_options = {
    ipv6Support = "disable"
  }
}

resource "alicloud_cen_transit_router_vpc_attachment" "att_app1" {
  cen_id            = alicloud_cen_instance.cen.id
  transit_router_id = alicloud_cen_transit_router.tr.transit_router_id
  vpc_id            = alicloud_vpc.app1.id

  transit_router_vpc_attachment_name = "${local.system_prefix}-att-app1"
  auto_publish_route_enabled         = false

  zone_mappings {
    vswitch_id = alicloud_vswitch.app1_inst_b.id
    zone_id    = var.az_b
  }

  zone_mappings {
    vswitch_id = alicloud_vswitch.app1_inst_c.id
    zone_id    = var.az_c
  }
}

resource "alicloud_cen_transit_router_vpc_attachment" "att_app2" {
  cen_id            = alicloud_cen_instance.cen.id
  transit_router_id = alicloud_cen_transit_router.tr.transit_router_id
  vpc_id            = alicloud_vpc.app2.id

  transit_router_vpc_attachment_name = "${local.system_prefix}-att-app2"
  auto_publish_route_enabled         = false

  zone_mappings {
    vswitch_id = alicloud_vswitch.app2_inst_b.id
    zone_id    = var.az_b
  }

  zone_mappings {
    vswitch_id = alicloud_vswitch.app2_inst_c.id
    zone_id    = var.az_c
  }
}

########################
# 6. Security Groups (LAB: allow-all)
########################

resource "alicloud_security_group" "sec_fw_sg" {
  vpc_id              = alicloud_vpc.sec.id
  security_group_name = "${local.system_prefix}-sec-fw-sg"
  resource_group_id   = local.target_rg_id
}

resource "alicloud_security_group_rule" "sec_fw_allow_all_in" {
  type              = "ingress"
  ip_protocol       = "all"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.sec_fw_sg.id
}

resource "alicloud_security_group_rule" "sec_fw_allow_all_out" {
  type              = "egress"
  ip_protocol       = "all"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.sec_fw_sg.id
}

resource "alicloud_security_group" "app1_sg" {
  vpc_id              = alicloud_vpc.app1.id
  security_group_name = "${local.system_prefix}-app1-sg"
  resource_group_id   = local.target_rg_id
}

resource "alicloud_security_group_rule" "app1_allow_all_in" {
  type              = "ingress"
  ip_protocol       = "all"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.app1_sg.id
}

resource "alicloud_security_group_rule" "app1_allow_all_out" {
  type              = "egress"
  ip_protocol       = "all"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.app1_sg.id
}

resource "alicloud_security_group" "app2_sg" {
  vpc_id              = alicloud_vpc.app2.id
  security_group_name = "${local.system_prefix}-app2-sg"
  resource_group_id   = local.target_rg_id
}

resource "alicloud_security_group_rule" "app2_allow_all_in" {
  type              = "ingress"
  ip_protocol       = "all"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.app2_sg.id
}

resource "alicloud_security_group_rule" "app2_allow_all_out" {
  type              = "egress"
  ip_protocol       = "all"
  policy            = "accept"
  cidr_ip           = "0.0.0.0/0"
  security_group_id = alicloud_security_group.app2_sg.id
}

########################
# 7. Firewalls (mgmt + private ENI) + MGMT EIPs
########################

resource "alicloud_instance" "fw1" {
  image_id             = var.image_id_palo_alto
  instance_type        = var.instance_type_fw
  instance_name        = "${local.system_prefix}-fw-1"
  security_groups      = [alicloud_security_group.sec_fw_sg.id]
  vswitch_id           = alicloud_vswitch.sec_fw1_mgmt.id
  system_disk_category = "cloud_essd"
  key_name             = var.key_pair_name
  resource_group_id    = local.target_rg_id
}

resource "alicloud_instance" "fw2" {
  image_id             = var.image_id_palo_alto
  instance_type        = var.instance_type_fw
  instance_name        = "${local.system_prefix}-fw-2"
  security_groups      = [alicloud_security_group.sec_fw_sg.id]
  vswitch_id           = alicloud_vswitch.sec_fw2_mgmt.id
  system_disk_category = "cloud_essd"
  key_name             = var.key_pair_name
  resource_group_id    = local.target_rg_id
}

resource "alicloud_network_interface" "fw1_private_eni" {
  vswitch_id         = alicloud_vswitch.sec_fw1_private.id
  security_group_ids = [alicloud_security_group.sec_fw_sg.id]
  description        = "fw1-private"
}

resource "alicloud_network_interface_attachment" "fw1_private_attach" {
  instance_id          = alicloud_instance.fw1.id
  network_interface_id = alicloud_network_interface.fw1_private_eni.id
}

resource "alicloud_network_interface" "fw2_private_eni" {
  vswitch_id         = alicloud_vswitch.sec_fw2_private.id
  security_group_ids = [alicloud_security_group.sec_fw_sg.id]
  description        = "fw2-private"
}

resource "alicloud_network_interface_attachment" "fw2_private_attach" {
  instance_id          = alicloud_instance.fw2.id
  network_interface_id = alicloud_network_interface.fw2_private_eni.id
}

resource "alicloud_eip_address" "fw1_mgmt_eip" {
  address_name         = "${local.system_prefix}-fw1-mgmt-eip"
  bandwidth            = 5
  internet_charge_type = "PayByTraffic"
}

resource "alicloud_eip_association" "fw1_mgmt_eip_assoc" {
  allocation_id = alicloud_eip_address.fw1_mgmt_eip.id
  instance_id   = alicloud_instance.fw1.id
  instance_type = "EcsInstance"
}

resource "alicloud_eip_address" "fw2_mgmt_eip" {
  address_name         = "${local.system_prefix}-fw2-mgmt-eip"
  bandwidth            = 5
  internet_charge_type = "PayByTraffic"
}

resource "alicloud_eip_association" "fw2_mgmt_eip_assoc" {
  allocation_id = alicloud_eip_address.fw2_mgmt_eip.id
  instance_id   = alicloud_instance.fw2.id
  instance_type = "EcsInstance"
}

########################
# 8. App ECS (one per VPC)  (keep simple)
########################

resource "alicloud_instance" "app1_server" {
  image_id             = var.image_id_ubuntu
  instance_type        = var.instance_type_app
  instance_name        = "${local.system_prefix}-app1-ubuntu"
  security_groups      = [alicloud_security_group.app1_sg.id]
  vswitch_id           = alicloud_vswitch.app1_inst_b.id
  system_disk_category = "cloud_essd"
  key_name             = var.key_pair_name
  resource_group_id    = local.target_rg_id
}

resource "alicloud_instance" "app2_server" {
  image_id             = var.image_id_ubuntu
  instance_type        = var.instance_type_app
  instance_name        = "${local.system_prefix}-app2-ubuntu"
  security_groups      = [alicloud_security_group.app2_sg.id]
  vswitch_id           = alicloud_vswitch.app2_inst_b.id
  system_disk_category = "cloud_essd"
  key_name             = var.key_pair_name
  resource_group_id    = local.target_rg_id
}

########################
# 8.1 Public ALB – App1 (Internet-facing) + backend app1_server
########################

resource "alicloud_alb_load_balancer" "app1_public_alb" {
  vpc_id                 = alicloud_vpc.app1.id
  address_type           = "Internet"
  address_allocated_mode = "Fixed"
  load_balancer_name     = "${local.system_prefix}-app1-public-alb"
  load_balancer_edition  = "Basic"
  resource_group_id      = local.target_rg_id

  load_balancer_billing_config {
    pay_type = "PayAsYouGo"
  }

  zone_mappings {
    vswitch_id = alicloud_vswitch.app1_alb_b.id
    zone_id    = var.az_b
  }

  zone_mappings {
    vswitch_id = alicloud_vswitch.app1_alb_c.id
    zone_id    = var.az_c
  }

  modification_protection_config {
    status = "NonProtection"
  }
}

resource "alicloud_alb_server_group" "app1_alb_sg" {
  protocol          = "HTTP"
  vpc_id            = alicloud_vpc.app1.id
  server_group_name = "${local.system_prefix}-app1-alb-sg"
  resource_group_id = local.target_rg_id

  sticky_session_config {
    sticky_session_enabled = false
  }

  health_check_config {
    health_check_enabled      = true
    health_check_protocol     = "HTTP"
    health_check_path         = "/"
    health_check_connect_port = 80
    healthy_threshold         = 3
    unhealthy_threshold       = 3
    health_check_timeout      = 5
    health_check_interval     = 5
    health_check_codes        = ["http_2xx", "http_3xx"]
    health_check_http_version = "HTTP1.1"
    health_check_method       = "GET"
  }

  servers {
    description = "${local.system_prefix}-app1-backend"
    port        = 80
    server_id   = alicloud_instance.app1_server.id
    server_ip   = alicloud_instance.app1_server.private_ip
    server_type = "Ecs"
    weight      = 100
  }
}

resource "alicloud_alb_listener" "app1_http_80" {
  load_balancer_id     = alicloud_alb_load_balancer.app1_public_alb.id
  listener_protocol    = "HTTP"
  listener_port        = 80
  listener_description = "${local.system_prefix}-app1-http-80"

  default_actions {
    type = "ForwardGroup"
    forward_group_config {
      server_group_tuples {
        server_group_id = alicloud_alb_server_group.app1_alb_sg.id
      }
    }
  }
}

########################
# 8.2 Public ALB – App2 (Internet-facing) + backend app2_server
########################

resource "alicloud_alb_load_balancer" "app2_public_alb" {
  vpc_id                 = alicloud_vpc.app2.id
  address_type           = "Internet"
  address_allocated_mode = "Fixed"
  load_balancer_name     = "${local.system_prefix}-app2-public-alb"
  load_balancer_edition  = "Basic"
  resource_group_id      = local.target_rg_id

  load_balancer_billing_config {
    pay_type = "PayAsYouGo"
  }

  zone_mappings {
    vswitch_id = alicloud_vswitch.app2_alb_b.id
    zone_id    = var.az_b
  }

  zone_mappings {
    vswitch_id = alicloud_vswitch.app2_alb_c.id
    zone_id    = var.az_c
  }

  modification_protection_config {
    status = "NonProtection"
  }
}

resource "alicloud_alb_server_group" "app2_alb_sg" {
  protocol          = "HTTP"
  vpc_id            = alicloud_vpc.app2.id
  server_group_name = "${local.system_prefix}-app2-alb-sg"
  resource_group_id = local.target_rg_id

  sticky_session_config {
    sticky_session_enabled = false
  }

  health_check_config {
    health_check_enabled      = true
    health_check_protocol     = "HTTP"
    health_check_path         = "/"
    health_check_connect_port = 80
    healthy_threshold         = 3
    unhealthy_threshold       = 3
    health_check_timeout      = 5
    health_check_interval     = 5
    health_check_codes        = ["http_2xx", "http_3xx"]
    health_check_http_version = "HTTP1.1"
    health_check_method       = "GET"
  }

  servers {
    description = "${local.system_prefix}-app2-backend"
    port        = 80
    server_id   = alicloud_instance.app2_server.id
    server_ip   = alicloud_instance.app2_server.private_ip
    server_type = "Ecs"
    weight      = 100
  }
}

resource "alicloud_alb_listener" "app2_http_80" {
  load_balancer_id     = alicloud_alb_load_balancer.app2_public_alb.id
  listener_protocol    = "HTTP"
  listener_port        = 80
  listener_description = "${local.system_prefix}-app2-http-80"

  default_actions {
    type = "ForwardGroup"
    forward_group_config {
      server_group_tuples {
        server_group_id = alicloud_alb_server_group.app2_alb_sg.id
      }
    }
  }
}

########################
# 8.3 App IPv4 Gateway (IGW) - enabled
########################

resource "alicloud_vpc_ipv4_gateway" "app1_igw" {
  vpc_id            = alicloud_vpc.app1.id
  ipv4_gateway_name = "${local.system_prefix}-app1-igw"
  enabled           = true
}

resource "alicloud_vpc_ipv4_gateway" "app2_igw" {
  vpc_id            = alicloud_vpc.app2.id
  ipv4_gateway_name = "${local.system_prefix}-app2-igw"
  enabled           = true
}

########################
# 9. GWLB + PrivateLink Service
########################

resource "alicloud_gwlb_load_balancer" "gwlb" {
  vpc_id             = alicloud_vpc.sec.id
  load_balancer_name = "${local.system_prefix}-gwlb"

  # IMPORTANT: set it to what the provider/API normalizes to
  address_ip_version = "Ipv4"

  zone_mappings {
    zone_id    = var.az_b
    vswitch_id = alicloud_vswitch.sec_fw1_private.id
  }

  zone_mappings {
    zone_id    = var.az_c
    vswitch_id = alicloud_vswitch.sec_fw2_private.id
  }

  lifecycle {
    ignore_changes = [zone_mappings]
  }
}

resource "alicloud_gwlb_server_group" "fw_group" {
  server_group_name = "${local.system_prefix}-gwlb-fw-sg"
  vpc_id            = alicloud_vpc.sec.id
  protocol          = "GENEVE"
  scheduler         = "2TCH"

  health_check_config {
    health_check_enabled         = true
    health_check_protocol        = "HTTP"
    health_check_path            = "/php/login.php"
    health_check_connect_port    = 80
    healthy_threshold            = 3
    unhealthy_threshold          = 3
    health_check_connect_timeout = 5
    health_check_interval        = 5
    health_check_http_code       = ["http_2xx"]
  }

  depends_on = [
    alicloud_network_interface_attachment.fw1_private_attach,
    alicloud_network_interface_attachment.fw2_private_attach,
  ]

  servers {
    server_type = "Eni"
    server_id   = alicloud_network_interface.fw1_private_eni.id
  }

  servers {
    server_type = "Eni"
    server_id   = alicloud_network_interface.fw2_private_eni.id
  }
}

resource "alicloud_privatelink_vpc_endpoint_service" "gwlb_svc" {
  service_description    = "${local.system_prefix}-gwlb-service"
  auto_accept_connection = true
  service_resource_type  = "gwlb"
  resource_group_id      = local.target_rg_id
}

resource "alicloud_privatelink_vpc_endpoint_service_resource" "gwlb_service_binding_b" {
  service_id    = alicloud_privatelink_vpc_endpoint_service.gwlb_svc.id
  resource_id   = alicloud_gwlb_load_balancer.gwlb.id
  resource_type = "gwlb"
  zone_id       = var.az_b
}

resource "alicloud_privatelink_vpc_endpoint_service_resource" "gwlb_service_binding_c" {
  service_id    = alicloud_privatelink_vpc_endpoint_service.gwlb_svc.id
  resource_id   = alicloud_gwlb_load_balancer.gwlb.id
  resource_type = "gwlb"
  zone_id       = var.az_c
}

resource "alicloud_gwlb_listener" "gwlb_listener" {
  listener_description = "${local.system_prefix}-gwlb-listener"
  server_group_id      = alicloud_gwlb_server_group.fw_group.id
  load_balancer_id     = alicloud_gwlb_load_balancer.gwlb.id
}

########################
# 10. Double GWLBe per VPC (NO hyphens in resource names!)
########################

resource "alicloud_privatelink_vpc_endpoint" "gwlbe_sec_b" {
  service_id        = alicloud_privatelink_vpc_endpoint_service.gwlb_svc.id
  vpc_id            = alicloud_vpc.sec.id
  vpc_endpoint_name = "${local.system_prefix}-sec-gwlbe-b"
  endpoint_type     = "GatewayLoadBalancer"
}

resource "alicloud_privatelink_vpc_endpoint" "gwlbe_sec_c" {
  service_id        = alicloud_privatelink_vpc_endpoint_service.gwlb_svc.id
  vpc_id            = alicloud_vpc.sec.id
  vpc_endpoint_name = "${local.system_prefix}-sec-gwlbe-c"
  endpoint_type     = "GatewayLoadBalancer"
}

resource "alicloud_privatelink_vpc_endpoint" "gwlbe_app1_b" {
  service_id        = alicloud_privatelink_vpc_endpoint_service.gwlb_svc.id
  vpc_id            = alicloud_vpc.app1.id
  vpc_endpoint_name = "${local.system_prefix}-app1-gwlbe-b"
  endpoint_type     = "GatewayLoadBalancer"
}

resource "alicloud_privatelink_vpc_endpoint" "gwlbe_app1_c" {
  service_id        = alicloud_privatelink_vpc_endpoint_service.gwlb_svc.id
  vpc_id            = alicloud_vpc.app1.id
  vpc_endpoint_name = "${local.system_prefix}-app1-gwlbe-c"
  endpoint_type     = "GatewayLoadBalancer"
}

resource "alicloud_privatelink_vpc_endpoint" "gwlbe_app2_b" {
  service_id        = alicloud_privatelink_vpc_endpoint_service.gwlb_svc.id
  vpc_id            = alicloud_vpc.app2.id
  vpc_endpoint_name = "${local.system_prefix}-app2-gwlbe-b"
  endpoint_type     = "GatewayLoadBalancer"
}

resource "alicloud_privatelink_vpc_endpoint" "gwlbe_app2_c" {
  service_id        = alicloud_privatelink_vpc_endpoint_service.gwlb_svc.id
  vpc_id            = alicloud_vpc.app2.id
  vpc_endpoint_name = "${local.system_prefix}-app2-gwlbe-c"
  endpoint_type     = "GatewayLoadBalancer"
}

resource "alicloud_privatelink_vpc_endpoint_zone" "gwlbe_app1_b_zone" {
  endpoint_id = alicloud_privatelink_vpc_endpoint.gwlbe_app1_b.id
  vswitch_id  = alicloud_vswitch.app1_gwlb_b.id
  zone_id     = var.az_b

    depends_on = [
    alicloud_privatelink_vpc_endpoint.gwlbe_app1_b,
  ]
}

resource "alicloud_privatelink_vpc_endpoint_zone" "gwlbe_app1_c_zone" {
  endpoint_id = alicloud_privatelink_vpc_endpoint.gwlbe_app1_c.id
  vswitch_id  = alicloud_vswitch.app1_gwlb_c.id
  zone_id     = var.az_c

    depends_on = [
    alicloud_privatelink_vpc_endpoint.gwlbe_app1_c,
  ]
}

resource "alicloud_privatelink_vpc_endpoint_zone" "gwlbe_app2_b_zone" {
  endpoint_id = alicloud_privatelink_vpc_endpoint.gwlbe_app2_b.id
  vswitch_id  = alicloud_vswitch.app2_gwlb_b.id
  zone_id     = var.az_b

    depends_on = [
    alicloud_privatelink_vpc_endpoint.gwlbe_app2_b,
  ]
}

resource "alicloud_privatelink_vpc_endpoint_zone" "gwlbe_app2_c_zone" {
  endpoint_id = alicloud_privatelink_vpc_endpoint.gwlbe_app2_c.id
  vswitch_id  = alicloud_vswitch.app2_gwlb_c.id
  zone_id     = var.az_c

    depends_on = [
    alicloud_privatelink_vpc_endpoint.gwlbe_app2_c,
  ]
}

resource "alicloud_privatelink_vpc_endpoint_zone" "gwlbe_sec_b_zone" {
  endpoint_id = alicloud_privatelink_vpc_endpoint.gwlbe_sec_b.id
  vswitch_id  = alicloud_vswitch.sec_gwlb_b.id
  zone_id     = var.az_b

    depends_on = [
    alicloud_privatelink_vpc_endpoint.gwlbe_sec_b,
  ]
}

resource "alicloud_privatelink_vpc_endpoint_zone" "gwlbe_sec_c_zone" {
  endpoint_id = alicloud_privatelink_vpc_endpoint.gwlbe_sec_c.id
  vswitch_id  = alicloud_vswitch.sec_gwlb_c.id
  zone_id     = var.az_c

    depends_on = [
    alicloud_privatelink_vpc_endpoint.gwlbe_sec_c,
  ]
}

########################
# 12. CEN Route Tables
########################

resource "alicloud_cen_transit_router_route_table" "spoke_rt" {
  transit_router_id               = alicloud_cen_transit_router.tr.transit_router_id
  transit_router_route_table_name = "${local.system_prefix}-tr-spoke-rt"
}

resource "alicloud_cen_transit_router_route_entry" "spoke_default_to_security" {
  transit_router_route_table_id                     = alicloud_cen_transit_router_route_table.spoke_rt.transit_router_route_table_id
  transit_router_route_entry_destination_cidr_block = "0.0.0.0/0"
  transit_router_route_entry_next_hop_type          = "Attachment"
  transit_router_route_entry_next_hop_id            = alicloud_cen_transit_router_vpc_attachment.att_security.transit_router_attachment_id
}

resource "alicloud_cen_transit_router_route_table_association" "spoke_app1_assoc" {
  transit_router_route_table_id = alicloud_cen_transit_router_route_table.spoke_rt.transit_router_route_table_id
  transit_router_attachment_id  = alicloud_cen_transit_router_vpc_attachment.att_app1.transit_router_attachment_id
}

resource "alicloud_cen_transit_router_route_table_association" "spoke_app2_assoc" {
  transit_router_route_table_id = alicloud_cen_transit_router_route_table.spoke_rt.transit_router_route_table_id
  transit_router_attachment_id  = alicloud_cen_transit_router_vpc_attachment.att_app2.transit_router_attachment_id
}

resource "alicloud_cen_transit_router_route_table" "sec_rt" {
  transit_router_id               = alicloud_cen_transit_router.tr.transit_router_id
  transit_router_route_table_name = "${local.system_prefix}-tr-sec-rt"
}

resource "alicloud_cen_transit_router_route_entry" "sec_rt_to_app1" {
  transit_router_route_table_id                     = alicloud_cen_transit_router_route_table.sec_rt.transit_router_route_table_id
  transit_router_route_entry_destination_cidr_block = "10.20.0.0/16"
  transit_router_route_entry_next_hop_type          = "Attachment"
  transit_router_route_entry_next_hop_id            = alicloud_cen_transit_router_vpc_attachment.att_app1.transit_router_attachment_id
}

resource "alicloud_cen_transit_router_route_entry" "sec_rt_to_app2" {
  transit_router_route_table_id                     = alicloud_cen_transit_router_route_table.sec_rt.transit_router_route_table_id
  transit_router_route_entry_destination_cidr_block = "10.30.0.0/16"
  transit_router_route_entry_next_hop_type          = "Attachment"
  transit_router_route_entry_next_hop_id            = alicloud_cen_transit_router_vpc_attachment.att_app2.transit_router_attachment_id
}

resource "alicloud_cen_transit_router_route_table_association" "sec_rt_assoc_security" {
  transit_router_route_table_id = alicloud_cen_transit_router_route_table.sec_rt.transit_router_route_table_id
  transit_router_attachment_id  = alicloud_cen_transit_router_vpc_attachment.att_security.transit_router_attachment_id
}

########################
# 13. Security VPC Route Tables
########################

resource "alicloud_route_table" "sec_nat_b_rt" {
  vpc_id           = alicloud_vpc.sec.id
  route_table_name = "${local.system_prefix}-sec-nat-b-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "sec_nat_b_rt_attach" {
  route_table_id = alicloud_route_table.sec_nat_b_rt.id
  vswitch_id     = alicloud_vswitch.sec_nat_b.id
}

resource "alicloud_route_entry" "sec_nat_b_to_gwlbe_10_8" {
  route_table_id        = alicloud_route_table.sec_nat_b_rt.id
  destination_cidrblock = "10.0.0.0/8"
  nexthop_type          = "GatewayLoadBalancerEndpoint"
  nexthop_id            = alicloud_privatelink_vpc_endpoint.gwlbe_sec_b.id

    depends_on = [
    alicloud_route_table_attachment.sec_nat_b_rt_attach,
    alicloud_privatelink_vpc_endpoint.gwlbe_sec_b,
    alicloud_privatelink_vpc_endpoint_zone.gwlbe_sec_b_zone,
  ]
}

resource "alicloud_route_table" "sec_nat_c_rt" {
  vpc_id           = alicloud_vpc.sec.id
  route_table_name = "${local.system_prefix}-sec-nat-c-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "sec_nat_c_rt_attach" {
  route_table_id = alicloud_route_table.sec_nat_c_rt.id
  vswitch_id     = alicloud_vswitch.sec_nat_c.id
}

resource "alicloud_route_entry" "sec_nat_c_to_gwlbe_10_8" {
  route_table_id        = alicloud_route_table.sec_nat_c_rt.id
  destination_cidrblock = "10.0.0.0/8"
  nexthop_type          = "GatewayLoadBalancerEndpoint"
  nexthop_id            = alicloud_privatelink_vpc_endpoint.gwlbe_sec_c.id

    depends_on = [
    alicloud_route_table_attachment.sec_nat_c_rt_attach,
    alicloud_privatelink_vpc_endpoint.gwlbe_sec_c,
    alicloud_privatelink_vpc_endpoint_zone.gwlbe_sec_c_zone,
  ]
}

resource "alicloud_route_table" "sec_gwlbe_b_rt" {
  vpc_id           = alicloud_vpc.sec.id
  route_table_name = "${local.system_prefix}-sec-gwlbe-b-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "sec_gwlbe_b_rt_attach" {
  route_table_id = alicloud_route_table.sec_gwlbe_b_rt.id
  vswitch_id     = alicloud_vswitch.sec_gwlb_b.id
}

resource "alicloud_route_entry" "sec_gwlbe_b_to_tr_10_8" {
  route_table_id        = alicloud_route_table.sec_gwlbe_b_rt.id
  destination_cidrblock = "10.0.0.0/8"
  nexthop_type          = "Attachment"
  nexthop_id            = alicloud_cen_transit_router_vpc_attachment.att_security.transit_router_attachment_id
}

resource "alicloud_route_entry" "sec_gwlbe_b_to_nat_default" {
  route_table_id        = alicloud_route_table.sec_gwlbe_b_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "NatGateway"
  nexthop_id            = alicloud_nat_gateway.sec_nat_b.id
}

resource "alicloud_route_table" "sec_gwlbe_c_rt" {
  vpc_id           = alicloud_vpc.sec.id
  route_table_name = "${local.system_prefix}-sec-gwlbe-c-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "sec_gwlbe_c_rt_attach" {
  route_table_id = alicloud_route_table.sec_gwlbe_c_rt.id
  vswitch_id     = alicloud_vswitch.sec_gwlb_c.id
}

resource "alicloud_route_entry" "sec_gwlbe_c_to_tr_10_8" {
  route_table_id        = alicloud_route_table.sec_gwlbe_c_rt.id
  destination_cidrblock = "10.0.0.0/8"
  nexthop_type          = "Attachment"
  nexthop_id            = alicloud_cen_transit_router_vpc_attachment.att_security.transit_router_attachment_id
}

resource "alicloud_route_entry" "sec_gwlbe_c_to_nat_default" {
  route_table_id        = alicloud_route_table.sec_gwlbe_c_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "NatGateway"
  nexthop_id            = alicloud_nat_gateway.sec_nat_c.id
}

resource "alicloud_route_table" "sec_att_b_rt" {
  vpc_id           = alicloud_vpc.sec.id
  route_table_name = "${local.system_prefix}-sec-att-b-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "sec_att_b_rt_attach" {
  route_table_id = alicloud_route_table.sec_att_b_rt.id
  vswitch_id     = alicloud_vswitch.sec_att_b.id
}

resource "alicloud_route_entry" "sec_att_b_to_gwlbe_default" {
  route_table_id        = alicloud_route_table.sec_att_b_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "GatewayLoadBalancerEndpoint"
  nexthop_id            = alicloud_privatelink_vpc_endpoint.gwlbe_sec_b.id

    depends_on = [
    alicloud_route_table_attachment.sec_att_b_rt_attach,
    alicloud_privatelink_vpc_endpoint.gwlbe_sec_b,
    alicloud_privatelink_vpc_endpoint_zone.gwlbe_sec_b_zone,
  ]
}

resource "alicloud_route_table" "sec_att_c_rt" {
  vpc_id           = alicloud_vpc.sec.id
  route_table_name = "${local.system_prefix}-sec-att-c-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "sec_att_c_rt_attach" {
  route_table_id = alicloud_route_table.sec_att_c_rt.id
  vswitch_id     = alicloud_vswitch.sec_att_c.id
}

resource "alicloud_route_entry" "sec_att_c_to_gwlbe_default" {
  route_table_id        = alicloud_route_table.sec_att_c_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "GatewayLoadBalancerEndpoint"
  nexthop_id            = alicloud_privatelink_vpc_endpoint.gwlbe_sec_c.id

    depends_on = [
    alicloud_route_table_attachment.sec_att_c_rt_attach,
    alicloud_privatelink_vpc_endpoint.gwlbe_sec_c,
    alicloud_privatelink_vpc_endpoint_zone.gwlbe_sec_c_zone,
  ]
}

########################
# 14. App1 Route Tables
########################

resource "alicloud_route_table" "app1_instance_b_rt" {
  vpc_id           = alicloud_vpc.app1.id
  route_table_name = "${local.system_prefix}-app1-instance-b-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app1_instance_b_rt_attach" {
  route_table_id = alicloud_route_table.app1_instance_b_rt.id
  vswitch_id     = alicloud_vswitch.app1_inst_b.id
}

resource "alicloud_route_entry" "app1_instance_b_default_to_cen" {
  route_table_id        = alicloud_route_table.app1_instance_b_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Attachment"
  nexthop_id            = alicloud_cen_transit_router_vpc_attachment.att_app1.transit_router_attachment_id
}

resource "alicloud_route_table" "app1_instance_c_rt" {
  vpc_id           = alicloud_vpc.app1.id
  route_table_name = "${local.system_prefix}-app1-instance-c-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app1_instance_c_rt_attach" {
  route_table_id = alicloud_route_table.app1_instance_c_rt.id
  vswitch_id     = alicloud_vswitch.app1_inst_c.id
}

resource "alicloud_route_entry" "app1_instance_c_default_to_cen" {
  route_table_id        = alicloud_route_table.app1_instance_c_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Attachment"
  nexthop_id            = alicloud_cen_transit_router_vpc_attachment.att_app1.transit_router_attachment_id
}

resource "alicloud_route_table" "app1_alb_b_rt" {
  vpc_id           = alicloud_vpc.app1.id
  route_table_name = "${local.system_prefix}-app1-alb-b-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app1_alb_b_rt_attach" {
  route_table_id = alicloud_route_table.app1_alb_b_rt.id
  vswitch_id     = alicloud_vswitch.app1_alb_b.id
}

resource "alicloud_route_entry" "app1_alb_b_default_to_gwlbe" {
  route_table_id        = alicloud_route_table.app1_alb_b_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "GatewayLoadBalancerEndpoint"
  nexthop_id            = alicloud_privatelink_vpc_endpoint.gwlbe_app1_b.id

    depends_on = [
    alicloud_route_table_attachment.app1_alb_b_rt_attach,
    alicloud_privatelink_vpc_endpoint.gwlbe_app1_b,
    alicloud_privatelink_vpc_endpoint_zone.gwlbe_app1_b_zone,
  ]
}

resource "alicloud_route_table" "app1_alb_c_rt" {
  vpc_id           = alicloud_vpc.app1.id
  route_table_name = "${local.system_prefix}-app1-alb-c-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app1_alb_c_rt_attach" {
  route_table_id = alicloud_route_table.app1_alb_c_rt.id
  vswitch_id     = alicloud_vswitch.app1_alb_c.id
}

resource "alicloud_route_entry" "app1_alb_c_default_to_gwlbe" {
  route_table_id        = alicloud_route_table.app1_alb_c_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "GatewayLoadBalancerEndpoint"
  nexthop_id            = alicloud_privatelink_vpc_endpoint.gwlbe_app1_c.id

    depends_on = [
    alicloud_route_table_attachment.app1_alb_c_rt_attach,
    alicloud_privatelink_vpc_endpoint.gwlbe_app1_c,
    alicloud_privatelink_vpc_endpoint_zone.gwlbe_app1_c_zone,
  ]
}

resource "alicloud_route_table" "app1_gwlbe_b_rt" {
  vpc_id           = alicloud_vpc.app1.id
  route_table_name = "${local.system_prefix}-app1-gwlbe-b-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app1_gwlbe_b_rt_attach" {
  route_table_id = alicloud_route_table.app1_gwlbe_b_rt.id
  vswitch_id     = alicloud_vswitch.app1_gwlb_b.id
}

resource "alicloud_route_entry" "app1_gwlbe_b_default_to_igw" {
  route_table_id        = alicloud_route_table.app1_gwlbe_b_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Ipv4Gateway"
  nexthop_id            = alicloud_vpc_ipv4_gateway.app1_igw.id
}

resource "alicloud_route_table" "app1_gwlbe_c_rt" {
  vpc_id           = alicloud_vpc.app1.id
  route_table_name = "${local.system_prefix}-app1-gwlbe-c-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app1_gwlbe_c_rt_attach" {
  route_table_id = alicloud_route_table.app1_gwlbe_c_rt.id
  vswitch_id     = alicloud_vswitch.app1_gwlb_c.id
}

resource "alicloud_route_entry" "app1_gwlbe_c_default_to_igw" {
  route_table_id        = alicloud_route_table.app1_gwlbe_c_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Ipv4Gateway"
  nexthop_id            = alicloud_vpc_ipv4_gateway.app1_igw.id
}

resource "alicloud_route_table" "app1_igw_gw_rt" {
  vpc_id           = alicloud_vpc.app1.id
  route_table_name = "${local.system_prefix}-app1-igw-gw-rt"
  associate_type   = "Gateway"
}

resource "alicloud_vpc_gateway_route_table_attachment" "app1_igw_bind" {
  ipv4_gateway_id = alicloud_vpc_ipv4_gateway.app1_igw.id
  route_table_id  = alicloud_route_table.app1_igw_gw_rt.id
}

########################
# 15. App2 Route Tables
########################

resource "alicloud_route_table" "app2_instance_b_rt" {
  vpc_id           = alicloud_vpc.app2.id
  route_table_name = "${local.system_prefix}-app2-instance-b-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app2_instance_b_rt_attach" {
  route_table_id = alicloud_route_table.app2_instance_b_rt.id
  vswitch_id     = alicloud_vswitch.app2_inst_b.id
}

resource "alicloud_route_entry" "app2_instance_b_default_to_cen" {
  route_table_id        = alicloud_route_table.app2_instance_b_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Attachment"
  nexthop_id            = alicloud_cen_transit_router_vpc_attachment.att_app2.transit_router_attachment_id
}

resource "alicloud_route_table" "app2_instance_c_rt" {
  vpc_id           = alicloud_vpc.app2.id
  route_table_name = "${local.system_prefix}-app2-instance-c-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app2_instance_c_rt_attach" {
  route_table_id = alicloud_route_table.app2_instance_c_rt.id
  vswitch_id     = alicloud_vswitch.app2_inst_c.id
}

resource "alicloud_route_entry" "app2_instance_c_default_to_cen" {
  route_table_id        = alicloud_route_table.app2_instance_c_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Attachment"
  nexthop_id            = alicloud_cen_transit_router_vpc_attachment.att_app2.transit_router_attachment_id
}

resource "alicloud_route_table" "app2_alb_b_rt" {
  vpc_id           = alicloud_vpc.app2.id
  route_table_name = "${local.system_prefix}-app2-alb-b-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app2_alb_b_rt_attach" {
  route_table_id = alicloud_route_table.app2_alb_b_rt.id
  vswitch_id     = alicloud_vswitch.app2_alb_b.id
}

resource "alicloud_route_entry" "app2_alb_b_default_to_gwlbe" {
  route_table_id        = alicloud_route_table.app2_alb_b_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "GatewayLoadBalancerEndpoint"
  nexthop_id            = alicloud_privatelink_vpc_endpoint.gwlbe_app2_b.id

    depends_on = [
    alicloud_route_table_attachment.app2_alb_b_rt_attach,
    alicloud_privatelink_vpc_endpoint.gwlbe_app2_b,
    alicloud_privatelink_vpc_endpoint_zone.gwlbe_app2_b_zone,
  ]
}

resource "alicloud_route_table" "app2_alb_c_rt" {
  vpc_id           = alicloud_vpc.app2.id
  route_table_name = "${local.system_prefix}-app2-alb-c-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app2_alb_c_rt_attach" {
  route_table_id = alicloud_route_table.app2_alb_c_rt.id
  vswitch_id     = alicloud_vswitch.app2_alb_c.id
}

resource "alicloud_route_entry" "app2_alb_c_default_to_gwlbe" {
  route_table_id        = alicloud_route_table.app2_alb_c_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "GatewayLoadBalancerEndpoint"
  nexthop_id            = alicloud_privatelink_vpc_endpoint.gwlbe_app2_c.id

    depends_on = [
    alicloud_route_table_attachment.app2_alb_c_rt_attach,
    alicloud_privatelink_vpc_endpoint.gwlbe_app2_c,
    alicloud_privatelink_vpc_endpoint_zone.gwlbe_app2_c_zone,
  ]
}

resource "alicloud_route_table" "app2_gwlbe_b_rt" {
  vpc_id           = alicloud_vpc.app2.id
  route_table_name = "${local.system_prefix}-app2-gwlbe-b-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app2_gwlbe_b_rt_attach" {
  route_table_id = alicloud_route_table.app2_gwlbe_b_rt.id
  vswitch_id     = alicloud_vswitch.app2_gwlb_b.id
}

resource "alicloud_route_entry" "app2_gwlbe_b_default_to_igw" {
  route_table_id        = alicloud_route_table.app2_gwlbe_b_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Ipv4Gateway"
  nexthop_id            = alicloud_vpc_ipv4_gateway.app2_igw.id
}

resource "alicloud_route_table" "app2_gwlbe_c_rt" {
  vpc_id           = alicloud_vpc.app2.id
  route_table_name = "${local.system_prefix}-app2-gwlbe-c-rt"
  associate_type   = "VSwitch"
}

resource "alicloud_route_table_attachment" "app2_gwlbe_c_rt_attach" {
  route_table_id = alicloud_route_table.app2_gwlbe_c_rt.id
  vswitch_id     = alicloud_vswitch.app2_gwlb_c.id
}

resource "alicloud_route_entry" "app2_gwlbe_c_default_to_igw" {
  route_table_id        = alicloud_route_table.app2_gwlbe_c_rt.id
  destination_cidrblock = "0.0.0.0/0"
  nexthop_type          = "Ipv4Gateway"
  nexthop_id            = alicloud_vpc_ipv4_gateway.app2_igw.id
}

resource "alicloud_route_table" "app2_igw_gw_rt" {
  vpc_id           = alicloud_vpc.app2.id
  route_table_name = "${local.system_prefix}-app2-igw-gw-rt"
  associate_type   = "Gateway"
}

resource "alicloud_vpc_gateway_route_table_attachment" "app2_igw_bind" {
  ipv4_gateway_id = alicloud_vpc_ipv4_gateway.app2_igw.id
  route_table_id  = alicloud_route_table.app2_igw_gw_rt.id
}

############################################
# END main.tf
############################################