pipeline {
    agent any

    environment {
        DOCKER_IMAGE = 'jack1503/samson'
        IMAGE_TAG = 'latest'
        CONTAINER_NAME = 'samson_container'
    }

    stages {

        stage('Build Docker Image') {
            steps {
                sh 'docker build -t $DOCKER_IMAGE:$IMAGE_TAG .'
            }
        }

        stage('Login to Docker Hub') {
            steps {
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-cred',
                    usernameVariable: 'USERNAME',
                    passwordVariable: 'PASSWORD'
                )]) {

                    sh 'echo $PASSWORD | docker login -u $USERNAME --password-stdin'
                }
            }
        }

        stage('Push to Docker Hub') {
            steps {
                sh 'docker push $DOCKER_IMAGE:$IMAGE_TAG'
            }
        }

        stage('Deploy to EC2') {
            steps {
                sh '''
                docker rm -f $CONTAINER_NAME || true
                docker pull $DOCKER_IMAGE:$IMAGE_TAG
                docker run -d -p 80:80 --name $CONTAINER_NAME $DOCKER_IMAGE:$IMAGE_TAG
                '''
            }
        }
    }
}
