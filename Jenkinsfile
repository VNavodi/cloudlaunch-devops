
pipeline {
    agent any

    stages {
        stage('Start') {
            steps {
                echo 'CloudLaunch Jenkins Pipeline Started!'
            }
        }

        stage('Test') {
            steps {
                echo 'Jenkins is working successfully!'
            }
        }

        stage('Deploy Preparation') {
            steps {
                echo 'Preparing CloudLaunch CD Pipeline...'
            }
        }
    }

    post {
        success {
            echo 'CloudLaunch Pipeline Completed Successfully!'
        }
        failure {
            echo 'CloudLaunch Pipeline Failed!'
        }
    }
}
