terraform {
  required_version = ">= 1.5.0"

  backend "s3" {
    bucket         = "cs1nca-tfstate-131464424832-eu-central-1"
    key            = "cs1/dev/terraform.tfstate" 
    region         = "eu-central-1"
    dynamodb_table = "cs1nca-tflock"
    encrypt        = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
