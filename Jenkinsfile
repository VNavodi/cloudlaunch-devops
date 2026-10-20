pipeline {
    agent any
    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 20, unit: 'MINUTES')
    }
    parameters {
        string(name: 'IMAGE_TAG', defaultValue: 'v1', description: 'Existing immutable ECR image tag')
        booleanParam(name: 'DEPLOY_TO_EC2', defaultValue: false, description: 'Explicitly allow production promotion after preflight')
    }
    environment {
        AWS_DEFAULT_REGION = 'ap-southeast-2'
        AWS_CONFIG_FILE = '/var/jenkins_home/.aws/config'
    }
    stages {
        stage('Validate source') {
            steps {
                sh 'bash -n scripts/deploy.sh scripts/promote-container.sh scripts/rollback-container.sh'
            }
        }
        stage('AWS identity') {
            when { expression { return params.DEPLOY_TO_EC2 } }
            steps {
                sh 'aws sts get-caller-identity --query Account --output text | grep -Fx 636621822646'
            }
        }
        stage('Deploy via SSM') {
            steps {
                withEnv(["DEPLOY_ENABLED=${params.DEPLOY_TO_EC2 ? 'true' : 'false'}", "TARGET_IMAGE_TAG=${params.IMAGE_TAG}"]) {
                    sh 'bash scripts/deploy.sh "$TARGET_IMAGE_TAG"'
                }
            }
        }
    }
    post {
        success { echo 'CloudLaunch CD pipeline completed.' }
        failure { echo 'CloudLaunch CD failed. Check SSM command output and EC2 health.' }
    }
}
