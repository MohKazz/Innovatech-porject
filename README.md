# Innovatech Project

The goal of this project was to create a modern cloud-based infrastructure for Innovatech Solutions. This was achieved through the use of the AWS cloud Services, GitHub, Docker, Kubernetes, and Terraform.


## Introduction

Innovatech Solutions is a leading provider of innovative technology solutions. They have a large number of employees across the company, and they need a modern cloud-based infrastructure to support their operations.During the implementation, we prioritized scalability and security to ensure a robust environment for the company's operations.

## About

This repository contains the documentation and code required to set up the Innovatech infrastructure. It serves as a case study for modern cloud deployment strategies.

## Technologies

Amazon Web Services (AWS)
Infrastructure as Code (IaC) - Terraform
Containerization - Docker
Version Control - GitHub
Networking - Kubernetes
Security - IAM, Encryption, Security Hub, GuardDuty, Macie
CI/CD - GitHub Actions



## Implementation

The implementation of the Innovatech infrastructure involves the following steps:

1. Infrastructure as Code: The infrastructure is defined using Terraform, a configuration management system that automates the deployment and configuration of cloud resources.

2. Version Control: The infrastructure is managed using GitHub, a distributed version control system that allows for collaboration and versioning of the code.

3. Automation: The infrastructure is deployed using GitHub Actions, a continuous integration and continuous deployment system that automates the deployment process.

4. Network Isolation: The infrastructure is deployed in isolated subnets to ensure high availability and minimize the risk of service disruptions.

5. Security: The infrastructure is designed to meet the security requirements of the company, including encryption, access control, IAM roles, an IAM system for employee management running on keycloak, and monitoring.

6. Monitoring: The infrastructure is monitored using AWS services such as CloudWatch, and a monitoring dashboard is created by Grafana and Prometheus to track the performance of the infrastructure.

7. Cost Optimization: The infrastructure is optimized to minimize the cost of the company's operations, including the use of auto scaling, and right sizing of resources.


## Prerequisites
To get started with the Innovatech infrastructure, you will need to set up the following:

1. An active AWS account
2. Terraform installed locally
3. Git installed
4. Access to GitHub
5. Appropriate IAM permissions to create AWS resources
6. Kubernetes, and Docker installed

## Deployment

Clone the Repository: Clone the repository to your local machine.
        git clone https://github.com/MohKazz/Innovatech-porject.git
        cd Innovatech-porject

Now that you have the repository cloned to your local machine, you can proceed with the deployment process. There are two ways to deploy the Innovatech infrastructure:

**First way**: Directly connecting to the AWS account form your machine throgh the aws cli tool and then deploying the infrastructure as follows:
1. Install the AWS CLI tool on your machine.
        pip install awscli

2. Create an IAM user with the necessary permissions to deploy the infrastructure. Dont use the root user, please!!

3. Configure the AWS CLI tool by running the following command:
        aws configure

4. Then run the following command to initialize the infrastructure:
        terraform init

4. Run the following command to validate the infrastructure:
        terraform validate

5. Run the following command to plan the infrastructure:
        terraform plan

6. Run the following command to apply the infrastructure:
        terraform apply

**Second way**:  the second way is to push the changes to your repo and then the infrastructure is deployed using GitHub Actions as follows:

1. Go to Your AWS account and get the Access Key and Secret Key

2. Go to your repo on GitHub then navigate to the settings, then click on the Secrets nad variables tab, then click  on ACtions and click on New repository secret. and add the vlues for the following variables:
        AWS_ACCESS_KEY_ID
        AWS_REGION
        AWS_SECRET_ACCESS_KEY
        AWS_SESSION_TOKEN (only if using temporary credentials)
        SOC_EMAIL (the email you want to recieve alerts on)
        
3. Push the changes to your repo on GitHub and the workflow will test the infrastructure and deploy it automatically if it passes the tests.

4. Monitor the deployment process in the AWS console.
5. Monitor the performance of the infrastructure using the Grafana dashboard on the "monitoring EC2".

## Kubernetes:
Keycloak is deployed on EKS and is used for employee management. To use it you need to manually configure it after the deployment. you can run it by typing the following commands:
        kubectl apply -f  keycloak-namespace.yaml
        kubectl apply -f  1-postgres-keycloak.yaml
        kubectl apply -f  keycloak-deployment.yaml
        kubectl apply -f  keycloak-secret.yaml
        kubectl apply -f  keycloak-service.yaml     
Find the url by running the following command:
        kubectl get service -n keycloak       
You can log in to the admin console by typing the defaults username "admin" and passowrd "admin" in the console. You then need to configure the keycloak with your application.

## Conclusion

The Innovatech infrastructure has been successfully deployed and is now ready for use. The infrastructure is designed to meet the needs of the company, including scalability, security, and cost optimization.

