
locals {
  public_subnet_cidrs = [
    "10.20.0.0/20",
    "10.20.16.0/20",
  ]
  app_subnet_cidrs = [
    "10.20.32.0/20",
    "10.20.48.0/20",
  ]
  db_subnet_cidrs = [
    "10.20.64.0/20",
    "10.20.80.0/20",
  ]
}