// Jenkinsfile — SWE 645 Assignment 2 CI/CD pipeline. Written by Lizon Raj.
// On every push to GitHub, this pipeline builds a new Docker image tagged with the
// short git SHA, pushes it to Docker Hub, and rolls out the new image on EKS.

pipeline {
    // Run on the built-in Jenkins controller node (the EC2 itself).
    agent any

    options {
        // Fail the build if any single stage runs longer than 15 min — safety net for hung docker/kubectl calls.
        timeout(time: 15, unit: 'MINUTES')
        // Keep only the last 10 build histories to save disk on the t3.small.
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    environment {
        IMAGE      = 'lizonraj/lizon-swe645-hw2'   // Docker Hub repo
        DEPLOY     = 'lizon-site'                  // Kubernetes Deployment name
        CONTAINER  = 'lizon-site'                  // Container name inside the pod (must match deployment.yaml)
        NAMESPACE  = 'default'                     // Kubernetes namespace
        CLUSTER    = 'lizon-swe645'                // EKS cluster name (for logging)
        REGION     = 'us-east-1'                   // AWS region (for logging)
    }

    stages {

        stage('Checkout') {
            steps {
                // Pulls source code from the git repo configured in the Jenkins job.
                checkout scm
            }
        }

        stage('Compute tag') {
            steps {
                script {
                    // Short 7-char commit SHA — becomes the immutable image tag for this build.
                    // Using a unique tag per commit is critical: it forces Kubernetes to
                    // recognize a spec change and roll out new pods (:latest alone would not).
                    env.TAG = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                }
                echo "Building image tag: ${env.TAG}"
            }
        }

        stage('Docker build') {
            steps {
                // Build one image, tag it twice: with the SHA (drives EKS rollout) and with :latest (convenience pointer).
                sh 'docker build -t $IMAGE:$TAG -t $IMAGE:latest .'
            }
        }

        stage('Docker push') {
            steps {
                // Bind the credentials we stored in Jenkins as "dockerhub-creds" into env vars.
                withCredentials([usernamePassword(
                    credentialsId: 'dockerhub-creds',
                    usernameVariable: 'DH_USER',
                    passwordVariable: 'DH_PASS'
                )]) {
                    // IMPORTANT: single quotes on the outside so Groovy does NOT interpolate $DH_PASS
                    // into the command string (that would print the secret to build logs).
                    // The shell receives literal "$DH_PASS" and expands it at runtime, safely.
                    sh 'echo "$DH_PASS" | docker login -u "$DH_USER" --password-stdin'
                    sh 'docker push $IMAGE:$TAG'
                    sh 'docker push $IMAGE:latest'
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                // Point the running Deployment at the newly-pushed image.
                // Kubernetes detects the template change, spins up new pods with the new image,
                // and terminates old pods once new ones pass readiness probes (rolling update).
                sh 'kubectl set image deployment/$DEPLOY $CONTAINER=$IMAGE:$TAG -n $NAMESPACE'

                // Block until the rollout finishes — real success signal, not just "set image accepted".
                // If any new pod fails to become Ready within 3 min, this fails the pipeline.
                sh 'kubectl rollout status deployment/$DEPLOY -n $NAMESPACE --timeout=180s'
            }
        }
    }

    post {
        always {
            // Cleanup — "|| true" so a cleanup failure doesn't fail the whole build.
            sh 'docker logout || true'
            sh 'docker image prune -f || true'
        }
        success {
            echo "Deployed ${env.IMAGE}:${env.TAG} to EKS cluster ${env.CLUSTER}"
        }
        failure {
            echo "Build failed — check stage output above for the failing command."
        }
    }
}
