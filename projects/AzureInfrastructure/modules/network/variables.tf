variable "resource_group_name" { type = string }
variable "location" { type = string }

variable "vnet_name" {
  type    = string
  default = "telugu-pickles-vnet"
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.20.0.0/16"]
}

variable "aks_subnet_prefixes" {
  type    = list(string)
  default = ["10.20.0.0/22"]
}
