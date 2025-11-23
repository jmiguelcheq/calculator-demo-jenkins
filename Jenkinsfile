import groovy.json.JsonOutput

pipeline {
  agent any
  options { timestamps(); durabilityHint('PERFORMANCE_OPTIMIZED'); skipDefaultCheckout() }

  environment {
    GITHUB_REPO   = 'jmiguelcheq/calculator-demo-jenkins'
    TEST_PARENT   = 'calculator-test-demo-jenkins'
    TEST_BRANCH   = 'main'
    TEST_RUN_URL  = ''
    TESTED_COMMIT = ''
  }

  stages {

    /* ---------------------------------------------------------
     * CHECKOUT
     * --------------------------------------------------------- */
    stage('Checkout') {
      steps { checkout scm }
    }

    /* ---------------------------------------------------------
     * PERMISSIONS
     * --------------------------------------------------------- */
    stage('CI Permissions') {
      steps {
        sh '''
          set -eu
          [ -f ci/push_to_loki.sh ] && chmod +x ci/push_to_loki.sh || true
          [ -f ci/summarize_tests.sh ] && chmod +x ci/summarize_tests.sh || true
        '''
      }
    }

    /* ---------------------------------------------------------
     * GUARD DEPLOY COMMITS
     * --------------------------------------------------------- */
    stage('Guard: Skip deploy commits') {
      steps {
        script {
          def msg = sh(script: 'git log -1 --pretty=%B', returnStdout: true).trim()
          if (msg.toLowerCase().contains('[skip ci]')) {
            echo 'Detected [skip ci] deploy commit. Stopping pipeline early.'
            currentBuild.result = 'NOT_BUILT'
            // hard-stop so later stages don’t run
            error('[skip ci] deploy commit – aborting remaining stages.')
          }
        }
      }
    }

    /* ---------------------------------------------------------
     * BUILD APP
     * --------------------------------------------------------- */
    stage('Build / Package App') {
      steps {
        sh '''
          set -e
          rm -rf dist && mkdir -p dist
          cp -r docs/* dist/ || true
        '''
        archiveArtifacts artifacts: 'dist/**', allowEmptyArchive: true
      }
    }

    /* ---------------------------------------------------------
     * RUN AUTOMATION TESTS (full suite before any deploy)
     * --------------------------------------------------------- */
    stage('Run Automation Tests (Testing repo)') {
      when {
        anyOf {
          allOf { changeRequest(); expression { env.CHANGE_TARGET == 'main' } }
          branch 'main'
        }
      }
      steps {
        script {

          // Get safe commit SHA for PR or branch builds
          def commitSha = sh(script: "git rev-parse HEAD", returnStdout: true).trim()
          env.TESTED_COMMIT = commitSha
          echo "Resolved commit SHA: ${commitSha}"

          def childPath = "${env.TEST_PARENT}/${env.TEST_BRANCH}"

          def buildRes = build(
            job: childPath,
            wait: true,
            propagate: false,
            parameters: [
              string(name: 'APP_REPO', value: env.GITHUB_REPO),
              string(name: 'APP_SHA',  value: commitSha), // LOCAL mode
              string(name: 'CALC_URL', value: ''),
              booleanParam(name: 'HEADLESS', value: true)
            ]
          )

          echo "Testing result: ${buildRes.result}"

          // Capture child run URL
          def runUrl = (buildRes?.absoluteUrl ?: '').trim()
          if (runUrl && !runUrl.endsWith('/')) runUrl += '/'
          env.TEST_RUN_URL = runUrl

          echo "Recorded TEST_RUN_URL=${env.TEST_RUN_URL}"

          currentBuild.result = buildRes?.result ?: 'FAILURE'

          // GitHub commit status (optional)
          if (env.TESTED_COMMIT) {
            withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {
              def state = (currentBuild.result == 'SUCCESS') ? 'success' : 'failure'
              def desc  = (state == 'success') ? 'Remote tests passed' : 'Remote tests failed'

              sh """
                set -eu
                curl -sS \
                  -H "Authorization: Bearer $GITHUB_TOKEN" \
                  -H "Accept: application/vnd.github+json" \
                  -X POST "https://api.github.com/repos/${GITHUB_REPO}/statuses/${env.TESTED_COMMIT}" \
                  -d '{ "state": "${state}", "context": "Remote UI Tests", "description": "${desc}", "target_url": "'$BUILD_URL'" }'
              """
            }
          }

          // PR failure comment
          if (env.CHANGE_ID && currentBuild.result != 'SUCCESS') {
            withCredentials([string(credentialsId: 'github-pat', variable: 'GITHUB_TOKEN')]) {

              def repoSlug = (env.CHANGE_URL ?: "")
                .replaceFirst('^.*github.com/', '')
                .replaceFirst('/pull/.*$', '')

              if (!repoSlug) repoSlug = env.GITHUB_REPO

              def body = """🚨 **Automation tests failed** for this PR.

**Test Run:** ${env.TEST_RUN_URL ?: 'N/A'}
**Allure Report:** ${env.TEST_RUN_URL ? env.TEST_RUN_URL + 'artifact/target/allure-single/' : 'N/A'}

> Conclusion: **FAILURE**"""

              def json = JsonOutput.toJson([body: body])

              sh """
                set -eu
                curl -sS \
                  -H "Authorization: Bearer $GITHUB_TOKEN" \
                  -H "Accept: application/vnd.github+json" \
                  -X POST "https://api.github.com/repos/${repoSlug}/issues/${env.CHANGE_ID}/comments" \
                  -d '${json}'
              """
            }
          }
        }
      }
    }

    /* ---------------------------------------------------------
     * DEPLOY STAGING (GitHub Pages under /docs/staging)
     * --------------------------------------------------------- */
    stage('Deploy to STAGING (main:/docs/staging)') {
      when { allOf { branch 'main'; expression { currentBuild.currentResult == 'SUCCESS' } } }
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

            # Staging under docs/staging (GitHub Pages root stays /docs)
            rm -rf docs/staging && mkdir -p docs/staging
            cp -r "$WORKSPACE/dist/"* docs/staging/ || true

            git add .
            git commit -m "[skip ci] Deploy STAGING (docs/staging) from build #$BUILD_NUMBER" || true
            git push origin main
          '''
        }
      }
    }

    /* ---------------------------------------------------------
     * SMOKE TEST STAGING
     * --------------------------------------------------------- */
    stage('Smoke Test STAGING') {
      when { allOf { branch 'main'; expression { currentBuild.currentResult == 'SUCCESS' } } }
      steps {
        script {
          def childPath  = "${env.TEST_PARENT}/${env.TEST_BRANCH}"
          def stagingUrl = 'https://jmiguelcheq.github.io/calculator-demo-jenkins/staging/'

          echo "Triggering full test suite as smoke against STAGING URL: ${stagingUrl}"

          def smokeRes = build(
            job: childPath,
            wait: true,
            propagate: false,
            parameters: [
              // REMOTE mode: no APP_SHA, just CALC_URL
              string(name: 'APP_REPO', value: env.GITHUB_REPO),
              string(name: 'APP_SHA',  value: ''),
              string(name: 'CALC_URL', value: stagingUrl),
              booleanParam(name: 'HEADLESS', value: true)
            ]
          )

          echo "Staging smoke test result: ${smokeRes.result}"

          if (smokeRes.result != 'SUCCESS') {
            error "Smoke tests on STAGING failed – blocking Production deploy."
          }
        }
      }
    }

    /* ---------------------------------------------------------
     * DEPLOY PRODUCTION (APPROVAL)
     * --------------------------------------------------------- */
    stage('Approve Production Deploy') {
      when { allOf { branch 'main'; expression { currentBuild.currentResult == 'SUCCESS' } } }
      steps {
        timeout(time: 2, unit: 'HOURS') {
          input message: 'Promote to PRODUCTION?', ok: 'Deploy'
        }
      }
    }

    /* ---------------------------------------------------------
     * DEPLOY PRODUCTION
     * --------------------------------------------------------- */
    stage('Deploy to PRODUCTION (main:/docs)') {
      when { allOf { branch 'main'; expression { currentBuild.currentResult == 'SUCCESS' } } }
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

  /* ---------------------------------------------------------
   * ALWAYS — PUSH TO LOKI
   * --------------------------------------------------------- */
  post {
    always {
      script {
        def resultVal     = currentBuild?.currentResult ?: 'FAILURE'
        def commitForLogs = env.TESTED_COMMIT ?: (env.GIT_COMMIT ?: 'unknown')

        withCredentials([
          string(credentialsId: 'grafana-loki-url',   variable: 'LOKI_URL'),
          usernamePassword(credentialsId: 'grafana-loki-user', passwordVariable: 'LOKI_TOKEN', usernameVariable: 'LOKI_USER')
        ]) {
          withEnv([
            "PIPE_RESULT=${resultVal}",
            "PIPE_COMMIT=${commitForLogs}"
          ]) {
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
                --arg commit "${PIPE_COMMIT}" \
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
