############################################
# outputs.tf
############################################

output "security_vpc_id" {
  value = alicloud_vpc.sec.id
}

output "app1_vpc_id" {
  value = alicloud_vpc.app1.id
}

output "app2_vpc_id" {
  value = alicloud_vpc.app2.id
}

output "fw1_mgmt_public_ip" {
  value = alicloud_eip_address.fw1_mgmt_eip.ip_address
}

output "fw2_mgmt_public_ip" {
  value = alicloud_eip_address.fw2_mgmt_eip.ip_address
}

output "app1_server_private_ip" {
  value = alicloud_instance.app1_server.private_ip
}

output "app2_server_private_ip" {
  value = alicloud_instance.app2_server.private_ip
}

output "app1_alb_public_address" {
  description = "Public address allocated to App1 ALB (may take time to appear in console)."
  value       = alicloud_alb_load_balancer.app1_public_alb.dns_name
}

output "app2_alb_public_address" {
  description = "Public address allocated to App2 ALB (may take time to appear in console)."
  value       = alicloud_alb_load_balancer.app2_public_alb.dns_name
}

output "gwlb_id" {
  value = alicloud_gwlb_load_balancer.gwlb.id
}

output "gwlbe_app1_b_id" {
  value = alicloud_privatelink_vpc_endpoint.gwlbe_app1_b.id
}

output "gwlbe_app1_c_id" {
  value = alicloud_privatelink_vpc_endpoint.gwlbe_app1_c.id
}

output "gwlbe_app2_b_id" {
  value = alicloud_privatelink_vpc_endpoint.gwlbe_app2_b.id
}

output "gwlbe_app2_c_id" {
  value = alicloud_privatelink_vpc_endpoint.gwlbe_app2_c.id
}

output "gwlbe_sec_b_id" {
  value = alicloud_privatelink_vpc_endpoint.gwlbe_sec_b.id
}

output "gwlbe_sec_c_id" {
  value = alicloud_privatelink_vpc_endpoint.gwlbe_sec_c.id
}

output "natgw_b_eip" {
  value = alicloud_eip_address.sec_nat_b_eip.ip_address
}

output "natgw_c_eip" {
  value = alicloud_eip_address.sec_nat_c_eip.ip_address
}