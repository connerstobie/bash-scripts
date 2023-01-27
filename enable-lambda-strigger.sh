#!/usr/local/bin/bash

# This script enables a list of lambda function triggers given the prefix of the lambda name as an arg
# This script adds to the AWS managed https://github.com/connerstobie/cross-account-amazon-dynamodb-replication

# Author: Conner Stobie
# Usage: ./enable-lambda-trigger.sh <target cluster> <source account>
# Example: ./enable-lambda-trigger.sh eos main
# SSO to the source account before running

export AWS_PROFILE=$2
export AWS_DEFAULT_REGION="us-west-2"
# Assumes function's already exist
FUNCTION_PREFIX=$1-dynamodb-migration

# Search for lambda functions based on given script args and output to a file
printf "\nSearching For DynamoDB Migration Lambdas\n\n"
aws lambda list-functions --query "Functions[?starts_with(FunctionName, '$FUNCTION_PREFIX')].FunctionName" --output table > lambdas.txt

# Preview returned lambdas's
cat lambdas.txt

# Check if returned lambdas are correct, wait for input 
printf "\n"
read -p "Are these Lambdas Correct? [y/n]: " -n 1 -r
# If correct, search lambda's trigger and output to file
if [[ $REPLY =~ ^[Yy]$ ]]; then
    printf "\n\nSearching For Specified Lambda Triggers\n\n"
    aws lambda list-event-source-mappings --query "EventSourceMappings[?contains(FunctionArn, '$FUNCTION_PREFIX')].UUID" --output yaml |awk '{print $2}' > triggers.txt
    printf "Lambda Triggers Found!\n"
else
    printf "\n"
    exit 1
fi

# Wait for user input to enable lambda triggers
printf "\n"
read -p "Enable Lambda Triggers? [y/n]: " -n 1 -r
if [[ $REPLY =~ ^[Yy]$ ]]; then
    printf "\n\nEnabling Lambda Triggers\n\n"
    while read line;
    do aws lambda update-event-source-mapping --uuid $line --enabled | grep -Ei "FunctionArn|State" | grep -v "StateTransitionReason" | tr -d '""' | tr -d ',';
    done < triggers.txt
else
   printf "\n"
   exit 1
fi

# Return lambda trigger states to ensure they were enabled
printf "\nGetting Updated Lambda Trigger States\n\n"
aws lambda list-event-source-mappings --query "EventSourceMappings[?contains(FunctionArn, '$FUNCTION_PREFIX')].UUID" --output yaml |awk '{print $2}' > triggers.txt
while read line;
do aws lambda get-event-source-mapping --uuid $line | grep -Ei "FunctionArn|State" | grep -v "StateTransitionReason" | tr -d '""' | tr -d ',';
done < triggers.txt | tee state.txt
if grep -q Enabled "state.txt"
then
    printf "\nSuccess!\n\n"
else
    printf "\nLambda Trigger Was Not Updated, Please Try Again\n"
    exit 1
  fi 

# Cleanup temporary files
rm triggers.txt && rm lambdas.txt && rm state.txt
