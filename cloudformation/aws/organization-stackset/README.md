# Britive - AWS Onboarding - CloudFormation - Organization Stackset

This deployment method will deploy a CloudFormation Stack which contains 2 resources.

1. A nested stack which will deploy the required integration resources in the organization management account (since CloudFormation Stacksets will not deploy to the management account)
2. A CloudFormation Stackset resource which will deploy the required integration resources to all member accounts in the AWS Organization.

This method requires a bit of setup so that we can re-use the template which actually deploys the integration resources.

All actions below should be performed in the AWS Organization management account.

1. Ensure Stacksets is enabled for your AWS Organization.
2. Create an S3 bucket in the AWS Organization management account (or use an existing one). Ensure the bucket is NOT public. No cross account access will be required.
3. Upload `britive_integration_resources.yaml` to this bucket.

Now we can proceed with deploying the resources. This can be done in the AWS Console if preferred. AWS CLI commands to deploy are provided below.

First, we need to modify `parameters.json` to set specific deployment parameters.

Now we can deploy the stack.

~~~bash
aws cloudformation deploy \
  --template-file deploy_britive_integration_resources.yaml \
  --stack-name britive \
  --parameter-overrides file://parameters.json \
  --region us-east-1 \
  --capabilities CAPABILITY_NAMED_IAM
~~~

Once the stack has been deployed, all required information to enter into the Britive UI will be provided in the Outputs section of the stack details.
An AWS CLI command to pull the outputs follows.

~~~bash
aws cloudformation describe-stacks \
  --stack-name britive \
  --region us-east-1 \
  --output text \
  --query 'Stacks[0].Outputs'
~~~