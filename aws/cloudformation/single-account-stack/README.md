# Britive - AWS Onboarding - CloudFormation - Single Account Stack

This deployment method will deploy a CloudFormation Stack which contains all the required integration resources Britive needs.

You can deploy this stack to 1 or more accounts as required.

This can be done in the AWS Console if preferred. AWS CLI commands to deploy are provided below.

First, we need to modify `parameters.json` to set specific deployment parameters.

Now we can deploy the stack.

~~~bash
aws cloudformation deploy \
  --template-file britive_integration_resources.yaml \
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