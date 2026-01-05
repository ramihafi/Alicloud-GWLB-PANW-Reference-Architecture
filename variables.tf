############################################
# variables.tf
############################################

variable "region" {
  description = "Region for all resources"
  type        = string
  default     = "cn-hongkong"
}

variable "az_b" {
  description = "Zone B"
  type        = string
  default     = "cn-hongkong-b"
}

variable "az_c" {
  description = "Zone C"
  type        = string
  default     = "cn-hongkong-c"
}

variable "system_prefix" {
  description = "Prefix for resource names"
  type        = string
  default     = "rhafi-gwlb"
}

variable "resource_group_name_regex" {
  description = "Optional Resource Group name regex. Use empty string to skip RG lookup."
  type        = string
  default     = ""
}

variable "cidr_security" {
  type    = string
  default = "10.10.0.0/16"
}

variable "cidr_app1" {
  type    = string
  default = "10.20.0.0/16"
}

variable "cidr_app2" {
  type    = string
  default = "10.30.0.0/16"
}

variable "instance_type_app" {
  type    = string
  default = "ecs.t6-c1m1.large"
}

variable "instance_type_fw" {
  type    = string
  default = "ecs.g5.xlarge"
}

variable "image_id_ubuntu" {
  description = "Ubuntu image ID"
  type        = string
}

variable "image_id_palo_alto" {
  description = "VM-Series marketplace image ID"
  type        = string
}

variable "key_pair_name" {
  description = "Existing SSH keypair name"
  type        = string
}