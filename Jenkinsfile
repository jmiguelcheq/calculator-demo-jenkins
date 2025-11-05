pipeline {
  agent any
  options { timestamps(); durabilityHint('PERFORMANCE_OPTIMIZED') }

  environment {
    // This app repo (owner/repo)
    GITHUB_REPO = 'jmiguelcheq/calculator-demo-jenkins'

    // Downstream testing multibranch job
    TEST_PARENT = 'calculator-test-demo-jenkins'
    TEST_BRANCH = 'main'
  }

  stages {

    stage('Checkout') {
      steps { checkout scm }
    }

    // Skip everything if the last commit is a deploy commit marked [skip ci]
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
      // Do not rebuild if only docs or docs-staging changed (deploy-only commit)
      when {
        not { changeset pattern: 'docs/**,docs-staging/**', comparator: 'ANT' }
      }
      steps {
        sh '''
          set -e
          rm -rf dist && mkdir -p dist
          # If you have a real build (npm/mvn), run it here.
          # For demo, copy ./docs as the built site.
          cp -r docs/* dist/ || true
        '''
        archiveArtifacts artifacts: 'dist/**', allowEmptyArchive: true
      }
    }

    stage('Run Automation Tests (Testing repo)') {
      // Run tests for PRs targeting main OR for main branch builds.
      // Also skip if the change was docs-only (deploy commit).
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
          def childPath = "${env.TEST_PARENT}/${env.TEST_BRANCH}"  // "<job>/<branch>"
          echo "Triggering downstream tests (LOCAL mode): ${childPath} @ ${GIT_COMMIT}"

          // Force LOCAL mode in the testing job by passing APP_SHA
          def buildRes = build job: childPath,
            wait: true,
            propagate: false,
            parameters: [
              string(name: 'APP_REPO', value: env.GITHUB_REPO),
              string(name: 'APP_SHA',  value: env.GIT_COMMIT),
              string(name: 'CALC_URL', value: ''),          // empty -> LOCAL path in test job
              booleanParam(name: 'HEADLESS', value: true)
            ]

          echo "Testing result: ${buildRes.result}"

          if (buildRes.result != 'SUCCESS') {
            currentBuild.result = 'FAILURE'

            // Commit status = failure
            if (env.GIT_COMMIT) {
              withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                sh '''
                  curl -sS -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
                    -X POST "https://api.github.com/repos/$GITHUB_REPO/statuses/$GIT_COMMIT" \
                    -d '{ "state": "failure", "context": "Remote UI Tests", "description": "Remote tests failed", "target_url": "'$BUILD_URL'" }'
                '''
              }
            }

            // --- PR comment on failure (posts a NEW comment each run) ---
            if (env.CHANGE_ID) {
              withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
                withEnv([
                  "RUN_URL=${buildRes.absoluteUrl}",
                  "ALLURE_HTML_URL=${buildRes.absoluteUrl}artifact/target/allure-single/index.html"
                ]) {
                  sh '''
                    set -e

                    pr="${CHANGE_ID}"

                    # Derive owner/repo from CHANGE_URL; fallback to GITHUB_REPO if not present
                    repo="${CHANGE_URL#*github.com/}"; repo="${repo%%/pull/*}"
                    [ -n "$repo" ] || repo="$GITHUB_REPO"

                    # Build markdown with expanded variables
body=$(cat <<EOF
🚨 **Automation tests failed** for this PR.

**Test Run:** $RUN_URL  
**Allure Report (View):** $ALLURE_HTML_URL

> Conclusion: **FAILURE**
EOF
)

                    # Escape for JSON
                    body_escaped=$(printf '%s' "$body" | sed 's/"/\\"/g')

                    # Post and show API result clearly
                    status=$(curl -sS -o /tmp/gh_resp.json -w "%{http_code}" \
                      -H "Authorization: Bearer $GITHUB_TOKEN" \
                      -H "Accept: application/vnd.github+json" \
                      -X POST "https://api.github.com/repos/$repo/issues/$pr/comments" \
                      -d "{ \"body\": \"$body_escaped\" }")

                    echo "GitHub comment API status: $status"
                    if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
                      echo "---- GitHub response body ----"
                      cat /tmp/gh_resp.json || true
                      echo "--------------------------------"
                      exit 1
                    fi
                  '''
                }
              }
            }

            error("Failing because testing repo reported ${buildRes.result}.")
          } else {
            // Commit status = success
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

    // ---------- Deployments (Pages = main / docs) ----------
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

            # Put preview under docs-staging/  -> https://<user>.github.io/<repo>/docs-staging/
            rm -rf docs-staging
            mkdir -p docs-staging
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
      steps {
        timeout(time: 2, unit: 'HOURS') {
          input message: 'Promote to PRODUCTION?', ok: 'Deploy'
        }
      }
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

            # Live site under docs/  -> GitHub Pages Settings: main / docs
            rm -rf docs
            mkdir -p docs
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
