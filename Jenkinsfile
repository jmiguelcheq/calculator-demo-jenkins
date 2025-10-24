pipeline {
  agent any
  options {
    timestamps()
    durabilityHint('PERFORMANCE_OPTIMIZED')
  }

  environment {
    GITHUB_REPO = 'jmiguelcheq/calculator-demo-jenkins'
    TEST_PARENT = 'calculator-test-demo-jenkins'
    TEST_BRANCH = 'main'
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build / Package App') {
      steps {
        sh '''
          rm -rf dist && mkdir -p dist
          # If you have a build step (npm build / maven package), do it here.
          # For the demo, copy ./docs as the artifact.
          cp -r docs/* dist/ || true
        '''
        archiveArtifacts artifacts: 'dist/**', allowEmptyArchive: true
      }
    }

    stage('Run Automation Tests (Testing repo)') {
      steps {
        script {
          // Use canonical job path: "<jobName>/<branchName>"
          def childPath = "${env.TEST_PARENT}/${env.TEST_BRANCH}"
          echo "Triggering: ${childPath} with APP_SHA=${GIT_COMMIT}"

          def buildRes = build job: childPath,
            wait: true,
            propagate: false,
            parameters: [
              string(name: 'APP_REPO', value: env.GITHUB_REPO),
              string(name: 'APP_SHA',  value: env.GIT_COMMIT),
              string(name: 'CALC_URL', value: 'https://jmiguelcheq.github.io/calculator-demo'),
              booleanParam(name: 'HEADLESS', value: true)
            ]

          echo "Testing result: ${buildRes.result}"
          if (buildRes.result != 'SUCCESS') {
            currentBuild.result = 'FAILURE'

            // 1) Set commit status = failure
            if (env.GIT_COMMIT) {
              withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                sh """
                  curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
                    -X POST "https://api.github.com/repos/${GITHUB_REPO}/statuses/${GIT_COMMIT}" \
                    -d '{ "state": "failure", "context": "Remote UI Tests", "description": "Remote tests failed", "target_url": "${buildRes.absoluteUrl}" }'
                """
              }
            }

            // 2) Comment on PR if this is a PR build (bash ${..#..} & heredoc -> use single quotes)
            if (env.CHANGE_ID) {
              withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                withEnv(["RUN_URL=${buildRes.absoluteUrl}"]) {
                  sh '''
                    pr=${CHANGE_ID}
                    repo=${CHANGE_URL#*github.com/}
                    repo=${repo%%/pull/*}

                    body=$(cat <<'EOT'
🚨 **Automation tests failed** for this PR.

Report & logs: $RUN_URL

> Conclusion: **FAILURE**
EOT
)
                    curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
                      -X POST "https://api.github.com/repos/$repo/issues/$pr/comments" \
                      -d @- <<JSON
{ "body": "$body" }
JSON
                  '''
                }
              }
            }

            error("Failing because testing repo reported ${buildRes.result}.")
          } else {
            // Set commit status = success
            if (env.GIT_COMMIT) {
              withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                sh """
                  curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
                    -X POST "https://api.github.com/repos/${GITHUB_REPO}/statuses/${GIT_COMMIT}" \
                    -d '{ "state": "success", "context": "Remote UI Tests", "description": "Remote tests passed", "target_url": "${buildRes.absoluteUrl}" }'
                """
              }
            }
          }
        }
      }
    }

    stage('Deploy to Staging (gh-pages-staging)') {
      when { branch 'main' }
      steps {
        withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
          sh '''
            set -e
            git config --global user.email "jenkins@local"
            git config --global user.name "Jenkins CI"

            rm -rf /tmp/gh && mkdir -p /tmp/gh && cd /tmp/gh
            git init
            git remote add origin "https://$GITHUB_TOKEN@github.com/$GITHUB_REPO.git"
            git checkout -B gh-pages-staging
            rm -rf ./*
            cp -r "/var/jenkins_home/workspace/$JOB_NAME/dist/"* . || true
            touch .nojekyll
            git add .
            git commit -m "Deploy staging from build #$BUILD_NUMBER" || true
            git push -f origin gh-pages-staging
          '''
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

    stage('Deploy to Production (gh-pages)') {
      when { branch 'main' }
      steps {
        withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
          sh '''
            set -e
            git config --global user.email "jenkins@local"
            git config --global user.name "Jenkins CI"

            rm -rf /tmp/ghprod && mkdir -p /tmp/ghprod && cd /tmp/ghprod
            git init
            git remote add origin "https://$GITHUB_TOKEN@github.com/$GITHUB_REPO.git"
            git checkout -B gh-pages
            rm -rf ./*
            cp -r "/var/jenkins_home/workspace/$JOB_NAME/dist/"* . || true
            touch .nojekyll
            git add .
            git commit -m "Deploy production from build #$BUILD_NUMBER" || true
            git push -f origin gh-pages
          '''
        }
      }
    }
  }
}
