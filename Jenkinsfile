pipeline {
    agent any
    
    environment {
        DOCKER_IMAGE = 'MYAPP:/latest'
        IMAGE_TAG = 'latest'
        CONTAINER_NAME = 'MYAPP_JACK_CONTAINER'
    }

    stages{
        stage('Build an docker image') {
            steps {
                sh 'docker build -t $DOCKER_IMAGE:$IMAGE_TAG .'
            }
        }
        stage(Login to docker hub) {
            steps {
                withCredentials([usernamepassword(
                    credentialsId: 'dockerhub-cred',
                    usernamevariable: 'USERNAME',
                    passwordvariable: 'PASSWORD'

                )]) {
                    sh 'echo $PASSWORD | docker login -u $USERNAME --password-stdin'
                }
            }
        }
        stage('push to docker hub') {
            steps {
                sh 'docker push $DOCKER_IMAGE:$IMAGE_TAG'
            }
        }
        stage('Deploy to EC2') {
            steps {
                sh '''
                docker rm-f $CONTAINER_NAME || true
                docker run -d -p 80:80 --name $CONTAINER_NAME $DOCKER_IMAGE:$IMAGE_TAG
                '''
            }
        }

}
