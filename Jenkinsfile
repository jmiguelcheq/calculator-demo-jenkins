import groovy.json.JsonOutput

pipeline {
  agent any
  options { timestamps(); durabilityHint('PERFORMANCE_OPTIMIZED'); skipDefaultCheckout() }

  environment {
    GITHUB_REPO  = 'jmiguelcheq/calculator-demo-jenkins'
    TEST_PARENT  = 'calculator-test-demo-jenkins'
    TEST_BRANCH  = 'main'
    TEST_RUN_URL = ''   // set after child job runs
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('CI Permissions') {
      steps {
        sh '''
          set -eu
          [ -f ci/push_to_loki.sh ] && chmod +x ci/push_to_loki.sh || true
          [ -f ci/summarize_tests.sh ] && chmod +x ci/summarize_tests.sh || true
        '''
      }
    }

    stage('Guard: Skip deploy commits') {
      steps {
        script {
          def msg = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
          if (msg.toLowerCase().contains('[skip ci]')) {
            echo 'Detected [skip ci] deploy commit. Skipping pipeline.'
            // currentBuild.description = 'Skipped: deploy commit'
            currentBuild.result = 'NOT_BUILT'
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

          def buildRes = build(
            job: childPath,
            wait: true,
            propagate: false,
            parameters: [
              string(name: 'APP_REPO', value: env.GITHUB_REPO),
              string(name: 'APP_SHA',  value: env.GIT_COMMIT),
              string(name: 'CALC_URL', value: ''),
              booleanParam(name: 'HEADLESS', value: true)
            ]
          )

          echo "Testing result: ${buildRes.result}"

          // ---- Capture and normalize test run URL ----
          def runUrl = (buildRes?.absoluteUrl ?: '').trim()
          if (runUrl && !runUrl.endsWith('/')) {
            runUrl = runUrl + '/'
          }
          env.TEST_RUN_URL = runUrl
          echo "Recorded TEST_RUN_URL=${env.TEST_RUN_URL}"

          // ---- Reflect child result on parent, but do NOT abort ----
          def childResult = (buildRes?.result ?: 'FAILURE')
          currentBuild.result = childResult

          // ---- GitHub commit status ----
          if (env.GIT_COMMIT) {
            withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
              def state = (childResult == 'SUCCESS') ? 'success' : 'failure'
              def desc  = (state == 'SUCCESS') ? 'Remote tests passed' : 'Remote tests failed'
              sh """
                set -eu
                curl -sS \
                  -H "Authorization: Bearer $GITHUB_TOKEN" \
                  -H "Accept: application/vnd.github+json" \
                  -X POST "https://api.github.com/repos/$GITHUB_REPO/statuses/$GIT_COMMIT" \
                  -d '{ "state": "${state}", "context": "Remote UI Tests", "description": "${desc}", "target_url": "'$BUILD_URL'" }'
              """
            }
          }

          // ---- PR failure comment (only for PRs + failed tests) ----
          if (env.CHANGE_ID && childResult != 'SUCCESS') {
            withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {

              // derive repo slug from CHANGE_URL, fallback to GITHUB_REPO
              def repoSlug = (env.CHANGE_URL ?: "")
                .replaceFirst('^.*github.com/', '')
                .replaceFirst('/pull/.*$', '')
              if (!repoSlug) {
                repoSlug = env.GITHUB_REPO
              }

              def runUrlForBody    = runUrl ?: 'N/A'
              def allureUrlForBody = runUrl ? runUrl + 'artifact/target/allure-single/' : 'N/A'

              def body = """🚨 **Automation tests failed** for this PR.

**Test Run:** ${runUrlForBody}
**Allure Report:** ${allureUrlForBody}

> Conclusion: **FAILURE**"""

              def json = JsonOutput.toJson([body: body])

              withEnv([
                "COMMENT_JSON=${json}",
                "REPO_SLUG=${repoSlug}"
              ]) {
                sh '''
                  set -eu
                  curl -sS \
                    -H "Authorization: Bearer $GITHUB_TOKEN" \
                    -H "Accept: application/vnd.github+json" \
                    -X POST "https://api.github.com/repos/$REPO_SLUG/issues/$CHANGE_ID/comments" \
                    -d "$COMMENT_JSON"
                '''
              }
            }
          }

          // no error() here — allow post + Loki stages to run
        }
      }
    }

    stage('Deploy to STAGING (main:/docs-staging)') {
      when {
        allOf {
          branch 'main'
          expression { currentBuild.currentResult == 'SUCCESS' }
        }
      }
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
      when {
        allOf {
          branch 'main'
          expression { currentBuild.currentResult == 'SUCCESS' }
        }
      }
      steps {
        timeout(time: 2, unit: 'HOURS') {
          input message: 'Promote to PRODUCTION?', ok: 'Deploy'
        }
      }
    }

    stage('Deploy to PRODUCTION (main:/docs)') {
      when {
        allOf {
          branch 'main'
          expression { currentBuild.currentResult == 'SUCCESS' }
        }
      }
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

  // ---- ALWAYS: push pipeline summary to Loki (success or failure) ----
  post {
    always {
      script {
        def resultVal = currentBuild?.currentResult ?: 'FAILURE'
        withCredentials([
          string(credentialsId: 'grafana-loki-url',   variable: 'LOKI_URL'),
          usernamePassword(credentialsId: 'grafana-loki-user', passwordVariable: 'LOKI_TOKEN', usernameVariable: 'LOKI_USER')
        ]) {
          withEnv(["PIPE_RESULT=${resultVal}"]) {
            sh '''
              set -eu

              if ! command -v jq >/dev/null 2>&1; then
                if   command -v apt-get >/dev/null 2>&1; then apt-get update -y && apt-get install -y jq >/dev/null 2>&1 || true;
                elif command -v apk     >/dev/null 2>&1; then apk add --no-cache jq >/dev/null 2>&1 || true;
                elif command -v yum     >/dev/null 2>&1; then yum install -y jq >/dev/null 2>&1 || true;
                fi
              fi

              STREAM_LABELS=$(jq -n \
                --arg job    "app-pipeline" \
                --arg repo   "${GITHUB_REPO}" \
                --arg branch "${BRANCH_NAME:-unknown}" \
                --arg build  "${BUILD_NUMBER}" \
                --arg status "${PIPE_RESULT}" \
                '{job:$job,repo:$repo,branch:$branch,build:$build,status:$status}')
              export STREAM_LABELS

              EXTRA_FIELDS=$(jq -n \
                --arg url    "${BUILD_URL}" \
                --arg commit "${GIT_COMMIT}" \
                --arg runurl "${TEST_RUN_URL:-}" \
                '{build_url:$url,commit:$commit,test_run:$runurl}')
              export EXTRA_FIELDS

              LOG_MESSAGE="App pipeline run ${PIPE_RESULT} for build ${BUILD_NUMBER}"
              export LOG_MESSAGE

              ./ci/push_to_loki.sh || echo "⚠️ Loki push failed (non-blocking)."
            '''
          }
        }
      }
    }
  }
}
