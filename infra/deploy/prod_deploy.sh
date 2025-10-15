#!/bin/bash

# Production Deployment Script for Face Analysis Pipeline
# This script deploys the latest Docker images to the production environment
# Usage: ./prod_deploy.sh

set -e  # Exit on any error

echo "Starting Production Deployment..."

# Configuration - Updated with actual values
AWS_ACCOUNT_ID="863518413893"
AWS_REGION="ap-southeast-2"
ECR_BACKEND_REPO="faceapp-backend"
ECR_FRONTEND_REPO="faceapp-frontend"
PROD_EC2_HOST="ec2-54-253-87-187.ap-southeast-2.compute.amazonaws.com"
# SSH key will be provided by Jenkins credentials as SSH_KEY environment variable

# Docker image tags - Using separate ECR repositories
BACKEND_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_BACKEND_REPO:latest"
FRONTEND_IMAGE="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_FRONTEND_REPO:latest"

echo "Configuration:"
echo "   AWS Account ID: $AWS_ACCOUNT_ID"
echo "   AWS Region: $AWS_REGION"
echo "   Backend ECR Repo: $ECR_BACKEND_REPO"
echo "   Frontend ECR Repo: $ECR_FRONTEND_REPO"
echo "   Production EC2 Host: $PROD_EC2_HOST"
echo "   Backend Image: $BACKEND_IMAGE"
echo "   Frontend Image: $FRONTEND_IMAGE"

# Function to execute commands on remote EC2 instance
execute_remote() {
    echo "Executing on remote host: $1"
    # Use SSH key provided by Jenkins credentials
    ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no ec2-user@$PROD_EC2_HOST "$1"
}

# Pre-deployment health check
echo "Pre-deployment health check..."
if ! curl -f http://$PROD_EC2_HOST/health > /dev/null 2>&1; then
    echo "Warning: Production service not responding before deployment"
else
    echo "Production service is currently healthy"
fi

# Step 1: Configure AWS credentials and login to ECR on remote host
echo "Step 1: Configuring AWS credentials and logging into ECR..."
execute_remote "aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID"
execute_remote "aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY"
execute_remote "aws configure set region $AWS_REGION"
execute_remote "aws configure set output json"

# Login to ECR
ECR_LOGIN_CMD=$(aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com)
execute_remote "$ECR_LOGIN_CMD"

# Step 2: Pull latest Docker images
echo "Step 2: Pulling latest Docker images..."
execute_remote "docker pull $BACKEND_IMAGE"
execute_remote "docker pull $FRONTEND_IMAGE"

# Step 3: Create backup of current deployment (optional but recommended)
echo "Step 3: Creating backup of current deployment..."
BACKUP_DIR="backup-$(date +%Y%m%d-%H%M%S)"
execute_remote "mkdir -p $BACKUP_DIR"
execute_remote "docker-compose -f docker-compose.remote.yml ps > $BACKUP_DIR/container-status.txt" || true

# Step 4: Stop existing containers gracefully
echo "Step 4: Stopping existing containers gracefully..."
execute_remote "docker-compose -f docker-compose.remote.yml down"

# Step 5: Start services with new images
echo "Step 5: Starting services with new images..."
execute_remote "docker-compose -f docker-compose.remote.yml up -d"

# Step 6: Wait for services to be healthy
echo "Step 6: Waiting for services to be healthy..."
sleep 45

# Step 7: Post-deployment health check
echo "Step 7: Post-deployment health check..."
if curl -f http://$PROD_EC2_HOST/health > /dev/null 2>&1; then
    echo "Production service is healthy after deployment"
else
    echo "Production service not responding after deployment"
    echo "Rolling back..."
    execute_remote "docker-compose -f docker-compose.remote.yml down"
    echo "Deployment failed - rolled back to previous state"
    exit 1
fi

# Step 8: Clean up unused Docker images
echo "Step 8: Cleaning up unused Docker images..."
execute_remote "docker image prune -f"

# Step 9: Show running containers
echo "Step 9: Showing running containers..."
execute_remote "docker ps"

echo "Production deployment completed successfully!"
echo ""
echo "Access your application:"
echo "   Frontend: http://$PROD_EC2_HOST"
echo "   Backend API: http://$PROD_EC2_HOST:8000"
echo "   Health Check: http://$PROD_EC2_HOST/health"
echo ""
echo "Next steps:"
echo "   - Run smoke tests: ./smoke_test.sh prod $PROD_EC2_HOST"
echo "   - Monitor CloudWatch metrics in AWS Console"
echo "   - Monitor logs: ssh to $PROD_EC2_HOST and run 'docker-compose logs -f'"
