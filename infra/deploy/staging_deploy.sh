#!/bin/bash

# Staging Deployment Script for Face Analysis Pipeline
# This script deploys the latest Docker images to the staging environment
# Usage: ./staging_deploy.sh

set -e  # Exit on any error

echo "Starting Staging Deployment..."

# Configuration - Updated with actual values
AWS_ACCOUNT_ID="863518413893"
AWS_REGION="ap-southeast-2"
ECR_BACKEND_REPO="faceapp-backend"
ECR_FRONTEND_REPO="faceapp-frontend"
STAGING_EC2_HOST="ec2-13-211-148-206.ap-southeast-2.compute.amazonaws.com"
# SSH key will be provided by Jenkins credentials as SSH_KEY environment variable

# Docker image tags - Using separate ECR repositories
BACKEND_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_BACKEND_REPO:latest"
FRONTEND_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_FRONTEND_REPO:latest"

echo "Configuration:"
echo "   AWS Account ID: $AWS_ACCOUNT_ID"
echo "   AWS Region: $AWS_REGION"
echo "   Backend ECR Repo: $ECR_BACKEND_REPO"
echo "   Frontend ECR Repo: $ECR_FRONTEND_REPO"
echo "   Staging EC2 Host: $STAGING_EC2_HOST"
echo "   Backend Image: $BACKEND_IMAGE"
echo "   Frontend Image: $FRONTEND_IMAGE"

# Function to execute commands on remote EC2 instance
execute_remote() {
    echo "Executing on remote host: $1"
    # Use SSH key provided by Jenkins credentials
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$STAGING_EC2_HOST "$1"
}

# Step 1: Configure AWS credentials and login to ECR on remote host
echo "Step 1: Configuring AWS credentials and logging into ECR..."
execute_remote "aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID"
execute_remote "aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY"
execute_remote "aws configure set region $AWS_REGION"
execute_remote "aws configure set output json"

# Login to ECR on remote host
execute_remote "aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"

# Step 2: Pull latest Docker images
echo "Step 2: Pulling latest Docker images..."
execute_remote "docker pull $BACKEND_IMAGE"
execute_remote "docker pull $FRONTEND_IMAGE"

# Step 3: Stop existing containers
echo "Step 3: Stopping existing containers..."
execute_remote "docker-compose -f docker-compose.remote.yml down" || echo "No existing containers to stop"

# Step 4: Start services with new images
echo "Step 4: Starting services with new images..."
execute_remote "docker-compose -f docker-compose.remote.yml up -d"

# Step 5: Wait for services to be healthy
echo "Step 5: Waiting for services to be healthy..."
sleep 30

# Step 6: Clean up unused Docker images
echo "Step 6: Cleaning up unused Docker images..."
execute_remote "docker image prune -f"

# Step 7: Show running containers
echo "Step 7: Showing running containers..."
execute_remote "docker ps"

echo "Staging deployment completed successfully!"
echo ""
echo "Access your application:"
echo "   Frontend: http://$STAGING_EC2_HOST"
echo "   Backend API: http://$STAGING_EC2_HOST:8000"
echo "   Health Check: http://$STAGING_EC2_HOST/health"
echo ""
echo "Next steps:"
echo "   - Run smoke tests: ./smoke_test.sh staging $STAGING_EC2_HOST"
echo "   - Monitor logs: ssh to $STAGING_EC2_HOST and run 'docker-compose logs -f'"
