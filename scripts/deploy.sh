#!/bin/bash

set -e

# Check required parameters
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <environment> <region> <action>"
    echo "Actions: create, update, delete"
    echo "Example: $0 dev us-east-1 create"
    exit 1
fi

ENVIRONMENT=$1
REGION=$2
ACTION=$3
TEMPLATE_BUCKET="vp-cloudformation-templates-${REGION}"  # Altere para um nome único
STACK_PREFIX="web-infrastructure"

# Configuration
TEMPLATES_DIR="./templates"
PARAMETERS_FILE="./parameters/${ENVIRONMENT}.json"
TEMP_PARAMETERS_FILE="./parameters/${ENVIRONMENT}.tmp.json"

# Validate prerequisites
command -v aws >/dev/null 2>&1 || { echo "AWS CLI is required but not installed. Aborting." >&2; exit 1; }

if [ ! -f "${PARAMETERS_FILE}" ]; then
    echo "Parameters file not found: ${PARAMETERS_FILE}"
    exit 1
fi

# Function to wait for stack operation to complete
wait_for_stack() {
    local stack_name=$1
    echo "Waiting for stack $stack_name..."
    
    aws cloudformation wait stack-${ACTION}-complete \
        --stack-name $stack_name \
        --region $REGION
    
    if [ $? -eq 0 ]; then
        echo "Stack $stack_name ${ACTION} completed successfully"
    else
        echo "Stack $stack_name ${ACTION} failed"
        exit 1
    fi
}

# Create S3 bucket if it doesn't exist
create_bucket_if_not_exists() {
    if ! aws s3 ls "s3://${TEMPLATE_BUCKET}" 2>&1 > /dev/null; then
        echo "Creating S3 bucket ${TEMPLATE_BUCKET}..."
        if [ "${REGION}" = "us-east-1" ]; then
            aws s3 mb "s3://${TEMPLATE_BUCKET}" --region ${REGION}
        else
            aws s3 mb "s3://${TEMPLATE_BUCKET}" --region ${REGION} --create-bucket-configuration LocationConstraint=${REGION}
        fi
        
        # Enable versioning on the bucket
        aws s3api put-bucket-versioning \
            --bucket ${TEMPLATE_BUCKET} \
            --versioning-configuration Status=Enabled
    fi
}

# Upload templates to S3
upload_templates() {
    echo "Uploading templates to S3..."
    aws s3 sync ${TEMPLATES_DIR} "s3://${TEMPLATE_BUCKET}/templates/" \
        --region ${REGION} \
        --delete
}

# Add TemplateBucket parameter to parameters array
create_parameters() {
    echo "[" > ${TEMP_PARAMETERS_FILE}
    echo "  {" >> ${TEMP_PARAMETERS_FILE}
    echo "    \"ParameterKey\": \"TemplateBucket\"," >> ${TEMP_PARAMETERS_FILE}
    echo "    \"ParameterValue\": \"${TEMPLATE_BUCKET}\"" >> ${TEMP_PARAMETERS_FILE}
    echo "  }," >> ${TEMP_PARAMETERS_FILE}
    
    # Copy existing parameters
    sed '1d;$d' ${PARAMETERS_FILE} >> ${TEMP_PARAMETERS_FILE}
    echo "]" >> ${TEMP_PARAMETERS_FILE}
}

# Main deployment logic
if [ "$ACTION" != "delete" ]; then
    create_bucket_if_not_exists
    upload_templates
    create_parameters

    # Deploy main stack
    stack_name="${STACK_PREFIX}-${ENVIRONMENT}"
    if [ "$ACTION" = "create" ]; then
        aws cloudformation create-stack \
            --stack-name ${stack_name} \
            --template-body file://${TEMPLATES_DIR}/main.yaml \
            --parameters file://${TEMP_PARAMETERS_FILE} \
            --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            --region ${REGION}
    else
        aws cloudformation update-stack \
            --stack-name ${stack_name} \
            --template-body file://${TEMPLATES_DIR}/main.yaml \
            --parameters file://${TEMP_PARAMETERS_FILE} \
            --capabilities CAPABILITY_NAMED_IAM CAPABILITY_AUTO_EXPAND \
            --region ${REGION}
    fi

    wait_for_stack ${stack_name}
    
    # Clean up temporary files
    rm -f ${TEMP_PARAMETERS_FILE}
else
    # Delete main stack (will delete all nested stacks)
    stack_name="${STACK_PREFIX}-${ENVIRONMENT}"
    aws cloudformation delete-stack \
        --stack-name ${stack_name} \
        --region ${REGION}

    wait_for_stack ${stack_name}
    
    # Optional: Delete the S3 bucket containing templates
    if aws s3 ls "s3://${TEMPLATE_BUCKET}" 2>&1 > /dev/null; then
        echo "Cleaning up template bucket..."
        aws s3 rb "s3://${TEMPLATE_BUCKET}" --force
    fi
fi

echo "Deployment process completed successfully!"