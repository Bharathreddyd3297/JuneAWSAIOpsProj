variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "cluster_name" { type = string }
variable "subnet_id" { type = string }
variable "node_vm_size" { type = string }
variable "node_count" { type = number }
variable "node_min_count" { type = number }
variable "node_max_count" { type = number }
