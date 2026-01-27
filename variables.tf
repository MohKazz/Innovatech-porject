variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "name" {
  type    = string
  default = "nca-innovatech-dev"
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
    project = "nca-innovatech"
    env     = "dev"
  }
}

variable "soc_email" {
   type = string
   default = "example@gmail.com"
   }
 
variable "db_username" {
  type    = string
  default = "admin"
}
variable "db_password" {
  type    = string
  default = "admin"
}
