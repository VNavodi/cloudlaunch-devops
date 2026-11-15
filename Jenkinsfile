pipeline {
    agent any

    options {
        timestamps()
        disableConcurrentBuilds()
        timeout(time: 10, unit: 'MINUTES')
    }

    parameters {
        string(
            name: 'IMAGE_TAG',
            defaultValue: 'v1',
            description: 'Image tag used to validate the production Compose configuration'
        )
    }

    stages {
        stage('Validate deployment script syntax') {
            steps {
                sh 'bash -n scripts/deploy-compose.sh'
                echo 'Deployment script syntax is valid.'
            }
        }

        stage('Validate production Compose configuration') {
            steps {
                sh '''
                    set -eu

                    if ! printf '%s' "$IMAGE_TAG" | grep -Eq '^[a-zA-Z0-9_.-]+$'; then
                        echo "ERROR: Invalid IMAGE_TAG."
                        exit 1
                    fi

                    IMAGE_TAG="$IMAGE_TAG" docker compose \
                        -f app/docker-compose.prod.yml config --quiet
                '''

                echo 'Production Compose configuration is valid.'
            }
        }
    }

    post {
        success {
            echo 'CloudLaunch validation pipeline completed. No deployment was performed.'
        }

        failure {
            echo 'CloudLaunch validation failed. Review the stage output.'
        }
    }
}
