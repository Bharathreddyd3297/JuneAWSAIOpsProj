variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "github_actions_principal" { type = string }

variable "name_prefix" {
  type    = string
  default = "telugupickles"
}
