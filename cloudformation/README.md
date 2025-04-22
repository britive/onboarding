# Britive's AWS Onboarding using CloudFormation

This repository contains various scripts and templates to assist with the integration of AWS into Britive platform. Customers can deploy the required Britive integration resources to an entire AWS Organization, single account or multiple accounts. 

## What It Does
The `cloudformation` directory includes CloudFormation templates designed to automate the setup and configuration of Britive's security and privilege access management (PAM) solutions within AWS environments. This can include creating IAM roles, policies, and other necessary resources to ensure secure and just in time (JIT) entitle management using Zero Standing Privilege (ZSP) standards. 

This CloudFormation setup is used during the onboarding of an AWS account(s) or organization in Britive. Once onboarded, the entire interaction is managed by Britive.


## Use and Benefits
1. **Automation**: By using CloudFormation templates, you can automate the deployment process, reducing manual effort and minimizing the risk of human error.
2. **Consistency**: Templates ensure that deployments are consistent across different environments, which is crucial for maintaining security standards.
3. **Scalability**: Automating the setup allows for easy scaling of resources as your needs grow, without having to manually configure each new instance.
4. **Security**: Britive's solutions focus on privileged access management and zero-trust enforcement, which are critical for maintaining a secure cloud environment.

Select the appropriate subdirectory for further details.
