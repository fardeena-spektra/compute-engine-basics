## MetaData
Question Type : Single Choice

## Question
1. Which combination of zone, machine type, image family, and network settings matches the required `ubuntu-vm` target?

## Options
Option 1 : `us-central1-a`, `e2-micro`, latest Ubuntu LTS, deployment-specific VPC and `10.10.0.0/24` subnet

Option 2 : `us-east1-b`, `e2-small`, Debian, default VPC and `10.20.0.0/24` subnet

Option 3 : `us-central1-a`, `e2-medium`, latest Ubuntu LTS, deployment-specific VPC and `10.10.0.0/24` subnet

Option 4 : `us-central1-b`, `e2-micro`, CentOS, default VPC and ephemeral external IP

## Answers
Option 1 : 2

## Correct Answer Feedback
Option 1 is correct because the target VM must use zone `us-central1-a`, machine type `e2-micro`, the latest Ubuntu LTS image, and the deployment-specific VPC subnet `10.10.0.0/24`.

## Incorrect Answer Feedback
Selected option is not correct. Option 1 is the correct answer.

## Number of Retries
1
