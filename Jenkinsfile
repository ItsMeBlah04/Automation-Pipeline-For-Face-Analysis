// Jenkinsfile for Face Analysis Pipeline CI/CD
// This declarative pipeline automates the entire build, test, and deployment process

pipeline {
    agent any

    environment {
        // AWS Configuration - Updated with actual values
        AWS_ACCOUNT_ID = '863518413893'
        AWS_REGION = 'ap-southeast-2'
        ECR_BACKEND_REPO = 'faceapp-backend'
        ECR_FRONTEND_REPO = 'faceapp-frontend'

        // EC2 Configuration - Updated with actual values
        STAGING_EC2_HOST = 'ec2-54-79-229-133.ap-southeast-2.compute.amazonaws.com'
        PROD_EC2_HOST = 'ec2-13-54-122-153.ap-southeast-2.compute.amazonaws.com'
        SSH_KEY_CREDENTIALS_ID = 'ssh-ec2'
        AWS_CREDENTIALS_ID = 'aws-creds'

        // Docker Configuration - Using separate ECR repositories
        DOCKER_BACKEND_IMAGE = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_BACKEND_REPO}:${env.BUILD_NUMBER}"
        DOCKER_FRONTEND_IMAGE = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_FRONTEND_REPO}:${env.BUILD_NUMBER}"
        DOCKER_BACKEND_LATEST = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_BACKEND_REPO}:latest"
        DOCKER_FRONTEND_LATEST = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_FRONTEND_REPO}:latest"

        // Deployment Configuration
        DEPLOYMENT_PATH = 'infra/deploy'
    }

    stages {
        stage('Initialize') {
            steps {
                script {
                    echo "================================"
                    echo "Building branch: ${env.BRANCH_NAME}"
                    echo "Build number: ${env.BUILD_NUMBER}"
                    echo "================================"
                }
            }
        }

        stage('Checkout') {
            steps {
                echo 'Checking out source code from GitHub...'
                checkout scm
            }
        }

        stage('Build Docker Images') {
            parallel {
                stage('Build Backend Image') {
                    steps {
                        echo 'Building backend Docker image...'
                        script {
                            docker.build("${DOCKER_BACKEND_IMAGE}", '-f infra/Dockerfile.backend .')
                        }
                    }
                }
                stage('Build Frontend Image') {
                    steps {
                        echo 'Building frontend Docker image...'
                        script {
                            docker.build("${DOCKER_FRONTEND_IMAGE}", '-f infra/Dockerfile.frontend .')
                        }
                    }
                }
            }
        }

        stage('Cleanup Previous Test Containers') {
            steps {
                echo 'Removing any leftover test containers from previous runs...'
                script {
                    sh """
                        # Remove all test containers matching our pattern
                        docker ps -a --filter "name=test-backend-" --filter "name=test-frontend-" -q | xargs -r docker rm -f || true
                        echo "Cleanup complete"
                    """
                }
            }
        }

        stage('Test Docker Images') {
            // NOTE: Using dynamic port allocation to avoid port conflicts when:
            // - Multiple builds run in parallel
            // - Previous containers haven't fully released ports
            // Docker assigns a random available port, which we query using 'docker port'
            parallel {
                stage('Test Backend Image') {
                    steps {
                        echo 'Testing backend Docker image...'
                        script {
                            sh """
                                # Define unique container name for this build
                                TEST_BACKEND_CONTAINER="test-backend-${BUILD_NUMBER}"
                                
                                # Force remove any leftover container from previous runs
                                docker rm -f \$TEST_BACKEND_CONTAINER 2>/dev/null || true
                                
                                # Run test container with dynamic port (-p 0:8000 assigns random available port)
                                docker run --rm -d --name \$TEST_BACKEND_CONTAINER -p 0:8000 ${DOCKER_BACKEND_IMAGE}
                                
                                # Set trap to cleanup on exit
                                trap "docker rm -f \$TEST_BACKEND_CONTAINER 2>/dev/null || true" EXIT
                                
                                # Get the dynamically assigned port
                                BACKEND_PORT=\$(docker port \$TEST_BACKEND_CONTAINER 8000 | cut -d: -f2)
                                echo "Backend test container running on port \$BACKEND_PORT"
                                
                                sleep 10
                                curl -f http://localhost:\$BACKEND_PORT/health || exit 1
                                curl -f http://localhost:\$BACKEND_PORT/ | grep -q 'Hello from backend' || exit 1
                                
                                echo "Backend tests passed on port \$BACKEND_PORT"
                            """
                        }
                    }
                }
                stage('Test Frontend Image') {
                    steps {
                        echo 'Testing frontend Docker image...'
                        script {
                            sh """
                                # Define unique container name for this build
                                TEST_FRONTEND_CONTAINER="test-frontend-${BUILD_NUMBER}"
                                
                                # Force remove any leftover container from previous runs
                                docker rm -f \$TEST_FRONTEND_CONTAINER 2>/dev/null || true
                                
                                # Run test container with dynamic port (-p 0:80 assigns random available port)
                                docker run --rm -d --name \$TEST_FRONTEND_CONTAINER -p 0:80 ${DOCKER_FRONTEND_IMAGE}
                                
                                # Set trap to cleanup on exit
                                trap "docker rm -f \$TEST_FRONTEND_CONTAINER 2>/dev/null || true" EXIT
                                
                                # Get the dynamically assigned port
                                FRONTEND_PORT=\$(docker port \$TEST_FRONTEND_CONTAINER 80 | cut -d: -f2)
                                echo "Frontend test container running on port \$FRONTEND_PORT"
                                
                                sleep 10
                                curl -f http://localhost:\$FRONTEND_PORT/health || exit 1
                                curl -f http://localhost:\$FRONTEND_PORT/ | grep -q 'Hello World Frontend' || exit 1
                                
                                echo "Frontend tests passed on port \$FRONTEND_PORT"
                            """
                        }
                    }
                }
            }
        }

        stage('Push to ECR') {
            steps {
                echo 'Pushing images to AWS ECR...'
                script {
                    // Use AWS credentials for ECR operations
                    withAWS(credentials: "${AWS_CREDENTIALS_ID}", region: "${AWS_REGION}") {
                        // Login to ECR
                        sh "aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

                        // Push backend image
                        sh "docker push ${DOCKER_BACKEND_IMAGE}"
                        sh "docker tag ${DOCKER_BACKEND_IMAGE} ${DOCKER_BACKEND_LATEST}"
                        sh "docker push ${DOCKER_BACKEND_LATEST}"

                        // Push frontend image
                        sh "docker push ${DOCKER_FRONTEND_IMAGE}"
                        sh "docker tag ${DOCKER_FRONTEND_IMAGE} ${DOCKER_FRONTEND_LATEST}"
                        sh "docker push ${DOCKER_FRONTEND_LATEST}"
                    }
                }
            }
        }

        stage('Deploy to Staging') {
            // Deploy to staging for both 'staging' and 'main' branches
            when {
                anyOf {
                    branch 'staging'
                    branch 'main'
                }
            }
            steps {
                echo 'Deploying to staging environment...'
                script {
                    // Copy deployment files to Jenkins workspace
                    sh "cp ${DEPLOYMENT_PATH}/staging_deploy.sh ."
                    sh "chmod +x staging_deploy.sh"

                    // Deploy to staging
                    withCredentials([
                        sshUserPrivateKey(credentialsId: "${SSH_KEY_CREDENTIALS_ID}", keyFileVariable: 'SSH_KEY'),
                        aws(credentialsId: "${AWS_CREDENTIALS_ID}", accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh """
                            export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
                            export AWS_REGION=${AWS_REGION}
                            export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
                            export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
                            ./staging_deploy.sh
                        """
                    }
                }
            }
        }

        stage('Smoke Test Staging') {
            when {
                anyOf {
                    branch 'staging'
                    branch 'main'
                }
            }
            steps {
                echo 'Running smoke tests on staging...'
                script {
                    sh "cp ${DEPLOYMENT_PATH}/smoke_test.sh ."
                    sh "chmod +x smoke_test.sh"

                    withCredentials([sshUserPrivateKey(credentialsId: "${SSH_KEY_CREDENTIALS_ID}", keyFileVariable: 'SSH_KEY')]) {
                        sh "./smoke_test.sh staging ${STAGING_EC2_HOST}"
                    }
                }
            }
        }

        stage('Approve Production Deployment') {
            // Only ask for approval when deploying from main branch
            when {
                branch 'main'
            }
            steps {
                script {
                    echo 'Waiting for approval to deploy to production...'
                    timeout(time: 15, unit: 'MINUTES') {
                        input message: 'Deploy to Production?', 
                              ok: 'Deploy',
                              submitter: 'admin'
                    }
                }
            }
        }

        stage('Deploy to Production') {
            // Only deploy to production from main branch
            when {
                branch 'main'
            }
            steps {
                echo 'Deploying to production environment...'
                script {
                    // Copy deployment files to Jenkins workspace
                    sh "cp ${DEPLOYMENT_PATH}/prod_deploy.sh ."
                    sh "chmod +x prod_deploy.sh"

                    // Deploy to production
                    withCredentials([
                        sshUserPrivateKey(credentialsId: "${SSH_KEY_CREDENTIALS_ID}", keyFileVariable: 'SSH_KEY'),
                        aws(credentialsId: "${AWS_CREDENTIALS_ID}", accessKeyVariable: 'AWS_ACCESS_KEY_ID', secretKeyVariable: 'AWS_SECRET_ACCESS_KEY')
                    ]) {
                        sh """
                            export AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID}
                            export AWS_REGION=${AWS_REGION}
                            export AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
                            export AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
                            ./prod_deploy.sh
                        """
                    }
                }
            }
        }

        stage('Smoke Test Production') {
            // Only test production when deployed from main branch
            when {
                branch 'main'
            }
            steps {
                echo 'Running smoke tests on production...'
                script {
                    withCredentials([sshUserPrivateKey(credentialsId: "${SSH_KEY_CREDENTIALS_ID}", keyFileVariable: 'SSH_KEY')]) {
                        sh "./smoke_test.sh prod ${PROD_EC2_HOST}"
                    }
                }
            }
        }

        stage('Cleanup') {
            steps {
                echo 'Cleaning up Docker images and temporary files...'
                script {
                    // Remove local Docker images to free up space
                    sh "docker rmi ${DOCKER_BACKEND_IMAGE} ${DOCKER_FRONTEND_IMAGE} || true"
                    sh "docker rmi ${DOCKER_BACKEND_LATEST} ${DOCKER_FRONTEND_LATEST} || true"

                    // Clean up deployment scripts
                    sh "rm -f staging_deploy.sh prod_deploy.sh smoke_test.sh"
                }
            }
        }
    }

    post {
        always {
            echo 'Pipeline execution completed'
        }
        success {
            script {
                echo 'Pipeline executed successfully!'
                echo "Branch: ${env.BRANCH_NAME}"
                echo 'Application URLs:'
                
                if (env.BRANCH_NAME == 'staging') {
                    echo "   Staging Frontend: http://${STAGING_EC2_HOST}"
                } else if (env.BRANCH_NAME == 'main') {
                    echo "   Staging Frontend: http://${STAGING_EC2_HOST}"
                    echo "   Production Frontend: http://${PROD_EC2_HOST}"
                }
            }
        }
        failure {
            script {
                echo 'Pipeline failed!'
                echo "Branch: ${env.BRANCH_NAME}"
                echo 'Check the Jenkins console output for details'
                echo 'Notify the development team'
            }
        }
    }
}
