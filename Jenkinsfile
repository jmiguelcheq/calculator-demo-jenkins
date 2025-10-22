pipeline {
  agent any
  options {
    timestamps()
    durabilityHint('PERFORMANCE_OPTIMIZED')
  }
  environment {
    // for PR comment + pushing deploy branches
    GITHUB_REPO    = 'jmiguelcheq/calculator-demo-jenkins'
    TEST_JOB_NAME  = 'calculator-test-demo-jenkins'
    TEST_BRANCH    = "main"
  }
  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build App') {
      steps {
        // Adjust to your build; Java/Maven example:
        sh 'mvn -B -q -DskipTests clean package'
        archiveArtifacts artifacts: 'target/**', allowEmptyArchive: true
      }
    }

    stage('Run Automation Tests (Other Repo)') {
      steps {
        script {
          // Ensure test multibranch child exists by scanning once, or use 'main'
          // child path usually: job/<PARENT>/job/<BRANCH>
          def childPath = "job/${env.TEST_JOB_NAME}/job/${env.TEST_BRANCH}"
          echo "Triggering ${childPath}"

          def result = build job: childPath, wait: true, propagate: false
          echo "Testing result: ${result.result}"

          if (result.result != 'SUCCESS') {
            currentBuild.result = 'FAILURE'
            // Post PR comment if this is a PR build
            if (env.CHANGE_ID) {
              withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                sh """
                  set -e
                  pr=\${CHANGE_ID}
                  repo=\${CHANGE_URL#*github.com/}
                  repo=\${repo%%/pull/*}
                  msg="❌ Automation tests **failed** in Jenkins build #${BUILD_NUMBER}. See ${BUILD_URL}"
                  curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \\
                    -X POST \\
                    -d '{\"body\":\"'"\${msg//\"/\\\"}"'\"}' \\
                    https://api.github.com/repos/\$repo/issues/\$pr/comments
                """
              }
            }
            error("Automation tests failed in testing repo.")
          }
        }
      }
    }

    stage('Deploy to Staging') {
      when { branch 'main' } // only deploy when main updates; remove if you want per-branch staging
      steps {
        withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
          sh """
            git config user.email "jenkins@local"
            git config user.name "Jenkins CI"
            # example: publish static site to gh-pages (staging) branch
            rm -rf dist && mkdir -p dist
            # COPY YOUR BUILD OUTPUT into dist (adjust below)
            cp -r target/* dist/ || true

            rm -rf /tmp/gh && mkdir -p /tmp/gh && cd /tmp/gh
            git init
            git remote add origin https://$GITHUB_TOKEN@github.com/${GITHUB_REPO}.git
            git checkout -b gh-pages-staging
            rm -rf ./*
            cp -r /var/jenkins_home/workspace/${JOB_NAME}/dist/* . || true
            git add .
            git commit -m "Deploy staging from build #${BUILD_NUMBER}" || true
            git push -f origin gh-pages-staging
          """
        }
      }
    }

    stage('Approve Production Deploy') {
      when { branch 'main' }
      steps {
        timeout(time: 2, unit: 'HOURS') {
          input message: 'Promote to PRODUCTION?', ok: 'Deploy'
        }
      }
    }

    stage('Deploy to Production') {
      when { branch 'main' }
      steps {
        withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
          sh """
            git config user.email "jenkins@local"
            git config user.name "Jenkins CI"
            # example: publish to gh-pages (production)
            rm -rf /tmp/ghprod && mkdir -p /tmp/ghprod && cd /tmp/ghprod
            git init
            git remote add origin https://$GITHUB_TOKEN@github.com/${GITHUB_REPO}.git
            git checkout -b gh-pages
            rm -rf ./*
            cp -r /var/jenkins_home/workspace/${JOB_NAME}/dist/* . || true
            git add .
            git commit -m "Deploy production from build #${BUILD_NUMBER}" || true
            git push -f origin gh-pages
          """
        }
      }
    }
  }

  post {
    failure {
      // Set explicit GitHub commit status (optional; Jenkins GitHub plugin already sets basic statuses)
      script {
        if (env.GIT_COMMIT) {
          withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
            sh """
              curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \\
                -X POST https://api.github.com/repos/${GITHUB_REPO}/statuses/${GIT_COMMIT} \\
                -d '{ "state": "failure", "context": "jenkins/app-pipeline", "description": "Build or tests failed", "target_url": "${BUILD_URL}" }'
            """
          }
        }
      }
    }
  }
}
