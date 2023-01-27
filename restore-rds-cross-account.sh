#!/usr/local/bin/bash

# This script takes a snapshot of an existing RDS DB in AWS account A and copies it to AWS account B
# then it restores the DB in account B from that snapshot

# Author: Conner Stobie
# usage  : ./restore-rds-cross-account.sh <env> <product>
# example: ./restore-rds-cross-account.sh npe service-a

# SSO to the 2 AWS accounts before running, Account / Profile information is
# hardcoded at the top of the script, so that needs to be adjusted for other
# accounts.
# TODO: make hardcoded values dynamic based on input

SOURCE_ACCOUNT="<source aws account profile>"
SOURCE_ACCOUNT_ID="<source account id>"
TARGET_ACCOUNT="<target aws account profile>"
TARGET_ACCOUNT_ID="<target account id>"

START_TIME=$(date +'%r')
echo "Start Time: $START_TIME"

export AWS_DEFAULT_REGION=us-west-2
ENV=$1
PRODUCT=$2

SOURCE_DB="$ENV-$PRODUCT-rds"
SNAPSHOT_ID="migration-$SOURCE_DB"

# source account
function setSourceAws() {
  echo "--- set AWS_PROFILE=$SOURCE_ACCOUNT ---"
  export AWS_PROFILE=$SOURCE_ACCOUNT
}

# target account
function setTargetAws() {
  echo "--- set AWS_PROFILE=$TARGET_ACCOUNT ---"
  export AWS_PROFILE=$TARGET_ACCOUNT
}

SNAPSHOT_STATUS="none"
function getSnapshotStatus() {
  SNAPSHOT_STATUS=$(aws rds describe-db-snapshots --query "DBSnapshots[?@.DBSnapshotIdentifier=='$SNAPSHOT_ID']" | jq -r '.[0].Status')
  echo "$(date +'%r'): Snapshot Status - $SNAPSHOT_STATUS"
}

RESTORED_DB_STATUS="none"
function getDBStatus() {
  RESTORED_DB_STATUS=$(aws rds describe-db-instances --query "DBInstances[?@.DBInstanceIdentifier=='$SOURCE_DB']" | jq -r '.[0].DBInstanceStatus')
  echo "$(date +'%r'): DB Status - $RESTORED_DB_STATUS"
}

### Source Account ###
setSourceAws

echo "--- Creating snapshot of $SOURCE_DB ---"
aws rds create-db-snapshot \
  --db-instance-identifier "$SOURCE_DB" \
  --db-snapshot-identifier "$SNAPSHOT_ID"

echo "--- Waiting for the source account snapshot to be available ---"
getSnapshotStatus
while [[ "$SNAPSHOT_STATUS" != "available" ]]; do
  sleep 10
  getSnapshotStatus
done

echo "--- Sharing snapshot ---"
aws rds modify-db-snapshot-attribute \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --attribute-name restore  \
  --values-to-add "[\"$TARGET_ACCOUNT_ID\"]"

### Target Account ###
setTargetAws

echo "--- Getting KMS key arn ---"
KMS_ALIAS_ARN=$(aws kms list-aliases --query "Aliases[?contains(@.AliasName,'$ENV-$PRODUCT')]" | jq -r '.[0].AliasArn')
echo "$KMS_ALIAS_ARN"

echo "--- Copying to target account ---"
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier "arn:aws:rds:us-west-2:$SOURCE_ACCOUNT_ID:snapshot:$SNAPSHOT_ID" \
  --target-db-snapshot-identifier "$SNAPSHOT_ID" \
  --kms-key-id "$KMS_ALIAS_ARN"

echo "--- Waiting for the target account snapshot to be available ---"
getSnapshotStatus
while [[ "$SNAPSHOT_STATUS" != "available" ]]; do
  sleep 10
  getSnapshotStatus
done

echo "--- Getting Security Group ID ---"
SG_ID=$(aws ec2 describe-security-groups --query "SecurityGroups[?contains(@.GroupName,'${ENV^^}-${PRODUCT^^}')]" | jq -r '.[0].GroupId')
echo "$SG_ID"

echo "--- Getting Parameter Group Name ---"
PARAM_GROUP=$(aws rds describe-db-parameter-groups --query "DBParameterGroups[?contains(@.DBParameterGroupName,'$ENV-$PRODUCT')]" | jq -r '.[0].DBParameterGroupName')
echo "$PARAM_GROUP"

echo "--- Getting Subnet Group Name ---"
SUBNET_NAME=$(aws rds describe-db-subnet-groups --query "DBSubnetGroups[?contains(@.DBSubnetGroupName,'$ENV-$PRODUCT')]" | jq -r '.[0].DBSubnetGroupName')
echo "$SUBNET_NAME"

echo "--- Restoring DB in target account ---"
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "$SOURCE_DB" \
  --db-snapshot-identifier "$SNAPSHOT_ID" \
  --db-subnet-group-name "$SUBNET_NAME" \
  --vpc-security-group-ids "$SG_ID" \
  --db-parameter-group-name "$PARAM_GROUP"


echo "--- Waiting for restored DB to be available ---"
getDBStatus
while [[ "$RESTORED_DB_STATUS" != "available" ]]; do
  sleep 10
  getDBStatus
done

END_TIME=$(date +'%r')
echo "Start Time: $START_TIME"
echo "End Time  : $END_TIME"