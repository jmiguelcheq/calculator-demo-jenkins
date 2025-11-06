pipeline {
  agent any
  options { timestamps(); durabilityHint('PERFORMANCE_OPTIMIZED') }

  environment {
    GITHUB_REPO = 'jmiguelcheq/calculator-demo-jenkins'
    TEST_PARENT = 'calculator-test-demo-jenkins'
    TEST_BRANCH = 'main'
  }

  stages {
    stage('Checkout') { steps { checkout scm } }

    stage('Guard: Skip deploy commits') {
      steps {
        script {
          def msg = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
          if (msg.toLowerCase().contains('[skip ci]')) {
            echo 'Detected [skip ci] deploy commit. Short-circuiting pipeline.'
            currentBuild.description = 'Skipped: deploy commit'
            return
          }
        }
      }
    }

    stage('Build / Package App') {
      when { not { changeset pattern: 'docs/**,docs-staging/**', comparator: 'ANT' } }
      steps {
        sh '''
          set -e
          rm -rf dist && mkdir -p dist
          cp -r docs/* dist/ || true
        '''
        archiveArtifacts artifacts: 'dist/**', allowEmptyArchive: true
      }
    }

    stage('Run Automation Tests (Testing repo)') {
      when {
        allOf {
          anyOf {
            allOf { changeRequest(); expression { env.CHANGE_TARGET == 'main' } }
            branch 'main'
          }
          not { changeset pattern: 'docs/**,docs-staging/**', comparator: 'ANT' }
        }
      }
      steps {
        script {
          def childPath = "${env.TEST_PARENT}/${env.TEST_BRANCH}"
          def buildRes = build job: childPath, wait: true, propagate: false, parameters: [
            string(name: 'APP_REPO', value: env.GITHUB_REPO),
            string(name: 'APP_SHA',  value: env.GIT_COMMIT),
            string(name: 'CALC_URL', value: ''),
            booleanParam(name: 'HEADLESS', value: true)
          ]
          echo "Testing result: ${buildRes.result}"

          if (buildRes.result != 'SUCCESS') {
            currentBuild.result = 'FAILURE'

            if (env.GIT_COMMIT) {
              withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                sh '''
                  curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
                    -X POST "https://api.github.com/repos/$GITHUB_REPO/statuses/$GIT_COMMIT" \
                    -d '{ "state": "failure", "context": "Remote UI Tests", "description": "Remote tests failed", "target_url": "'$BUILD_URL'" }'
                '''
              }
            }

            // ✅ Final safe PR comment on failure (no heredoc, no awk, fully portable)
            if (env.CHANGE_ID) {
              withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                withEnv([
                  "RUN_URL=${buildRes.absoluteUrl}",
                  "ALLURE_HTML_URL=${buildRes.absoluteUrl}artifact/target/allure-single"
                ]) {
                  sh '''
                    set -eu

                    pr=${CHANGE_ID}
                    repo=${CHANGE_URL#*github.com/}
                    repo=${repo%%/pull/*}
                    [ -n "$repo" ] || repo="$GITHUB_REPO"

                    # Build the JSON payload manually (single line with \\n)
                    json="{\\\"body\\\": \\\"🚨 **Automation tests failed** for this PR.\\\\n\\\\n**Test Run:** $RUN_URL  \\\\n**Allure Report (View):** $ALLURE_HTML_URL\\\\n\\\\n> Conclusion: **FAILURE**\\\"}"

                    echo "Posting PR comment to https://api.github.com/repos/$repo/issues/$pr/comments"
                    curl -sS \
                      -H "Authorization: Bearer $GITHUB_TOKEN" \
                      -H "Accept: application/vnd.github+json" \
                      -X POST "https://api.github.com/repos/$repo/issues/$pr/comments" \
                      -d "$json"
                  '''
                }
              }
            }
            // -------------------------------------------

            error("Failing because testing repo reported ${buildRes.result}.")
          } else {
            if (env.GIT_COMMIT) {
              withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                sh '''
                  curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
                    -X POST "https://api.github.com/repos/$GITHUB_REPO/statuses/$GIT_COMMIT" \
                    -d '{ "state": "success", "context": "Remote UI Tests", "description": "Remote tests passed", "target_url": "'$BUILD_URL'" }'
                '''
              }
            }
          }
        }
      }
    }

    stage('Deploy to STAGING (main:/docs-staging)') {
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
            git fetch origin main --depth=1
            git checkout -B main origin/main
            rm -rf docs-staging && mkdir -p docs-staging
            cp -r "$WORKSPACE/dist/"* docs-staging/ || true
            git add .
            git commit -m "[skip ci] Deploy STAGING (docs-staging) from build #$BUILD_NUMBER" || true
            git push origin main
          '''
        }
      }
    }

    stage('Approve Production Deploy') {
      when { branch 'main' }
      steps { timeout(time: 2, unit: 'HOURS') { input message: 'Promote to PRODUCTION?', ok: 'Deploy' } }
    }

    stage('Deploy to PRODUCTION (main:/docs)') {
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
            git fetch origin main --depth=1
            git checkout -B main origin/main
            rm -rf docs && mkdir -p docs
            cp -r "$WORKSPACE/dist/"* docs/ || true
            touch docs/.nojekyll
            git add .
            git commit -m "[skip ci] Deploy PRODUCTION (docs) from build #$BUILD_NUMBER" || true
            git push origin main
          '''
        }
      }
    }
  }
}
