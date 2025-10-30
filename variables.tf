variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  type    = string
  default = "cs1nca-dev"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "azs" {
  type    = list(string)
  default = ["eu-central-1a", "eu-central-1b"]
}

variable "tags" {
  type = map(string)
  default = {
    project = "cs1nca"
    env     = "dev"
  }
}


variable "db_username" {
  type    = string
  default = "admin_mo"
}
variable "db_password" {
  type    = string
  default = "admin_mo"
}
