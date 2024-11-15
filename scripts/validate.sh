#!/bin/bash

# Script to validate CloudFormation templates
# Usage: ./validate.sh <region>

set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <region>"
    echo "Example: $0 us-east-1"
    exit 1
fi

REGION=$1
TEMPLATES_DIR="./templates"

# Find all yaml/yml files recursively
find ${TEMPLATES_DIR} -type f \( -name "*.yaml" -o -name "*.yml" \) | while read template; do
    echo "Validating template: ${template}"
    aws cloudformation validate-template \
        --template-body file://${template} \
        --region ${REGION}
    
    if [ $? -eq 0 ]; then
        echo "✅ Template is valid: ${template}"
    else
        echo "❌ Template validation failed: ${template}"
        exit 1
    fi
done

echo "All templates validated successfully!"