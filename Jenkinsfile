pipeline {
  agent any
  options { timestamps(); disableConcurrentBuilds() }
  environment {
    GITHUB_OWNER   = 'jmiguelcheq'
    APP_REPO       = 'calculator-demo'
    TEST_JOB_PATH  = 'calculator-test-demo/main' // Jenkins job path for Repo B's main branch
    ARTIFACT_NAME  = 'site.zip'
  }

  triggers {
    // For Multibranch + webhook: Jenkins will auto-trigger on push/PR.
    // Without webhook, configure SCM polling in the job UI.
  }

  stages {
    stage('Checkout') {
      steps { checkout scm }
    }

    stage('Build & Package') {
      steps {
        bat '''
          if exist %ARTIFACT_NAME% del /f /q %ARTIFACT_NAME%
          powershell -Command "Compress-Archive -Path src\\* -DestinationPath %ARTIFACT_NAME%"
        '''
      }
      post {
        success { archiveArtifacts artifacts: "${ARTIFACT_NAME}", fingerprint: true }
      }
    }

    stage('Run Cross-Repo Tests') {
      steps {
        script {
          def run = build job: TEST_JOB_PATH,
                         parameters: [
                           string(name: 'UPSTREAM_BUILD_URL', value: env.BUILD_URL),
                           string(name: 'UPSTREAM_ARTIFACT',  value: ARTIFACT_NAME)
                         ],
                         propagate: false, wait: true

          if (run.result != 'SUCCESS') {
            currentBuild.result = 'FAILURE'
            setGitHubStatus('failure', "Automation tests failed", env.GIT_COMMIT)
            commentOnPRIfAny("❌ Automation tests **failed** in `${TEST_JOB_PATH}`. See upstream build: ${env.BUILD_URL}")
            error("Tests failed in ${TEST_JOB_PATH}")
          }
        }
      }
    }

    stage('Deploy to Staging') {
      when { branch 'main' }
      steps {
        // Demo deploy: copy artifact to a "staging" folder or publish to gh-pages/S3 etc.
        bat '''
          if not exist C:\\deploy\\staging mkdir C:\\deploy\\staging
          copy /y %WORKSPACE%\\%ARTIFACT_NAME% C:\\deploy\\staging\\%ARTIFACT_NAME%
        '''
        echo "Staging deployed to C:\\deploy\\staging\\${ARTIFACT_NAME}"
      }
    }

    stage('Manual Approval for Production') {
      when { branch 'main' }
      steps {
        input message: 'Approve deployment to PRODUCTION?', ok: 'Deploy'
      }
    }

    stage('Deploy to Production') {
      when { branch 'main' }
      steps {
        bat '''
          if not exist C:\\deploy\\prod mkdir C:\\deploy\\prod
          copy /y %WORKSPACE%\\%ARTIFACT_NAME% C:\\deploy\\prod\\%ARTIFACT_NAME%
        '''
        echo "Production deployed to C:\\deploy\\prod\\${ARTIFACT_NAME}"
      }
    }
  }

  post {
    success {
      setGitHubStatus('success', "Tests passed; staged & (if approved) prod deployed", env.GIT_COMMIT)
      commentOnPRIfAny("✅ Tests passed. Deployed to **staging**. Production deployment completed after approval.")
    }
    failure {
      // A final safety status; main failure handling already done above
      setGitHubStatus('failure', "Pipeline failed", env.GIT_COMMIT)
    }
  }
}

/**
 * Helpers — use a GitHub PAT credential id: 'github-pat'
 * For PRs in Multibranch, env.CHANGE_ID exists. Commit SHA is env.GIT_COMMIT.
 */
def setGitHubStatus(String state, String description, String sha) {
  withCredentials([string(credentialsId: 'github-pat', variable: 'GH')]) {
    powershell """
      \$body = @{
        state='${state}'
        description='${description}'
        context='jenkins/cicd'
        target_url='${env.BUILD_URL}'
      } | ConvertTo-Json
      Invoke-RestMethod -Method POST `
        -Uri "https://api.github.com/repos/${env.GITHUB_OWNER}/${env.JOB_NAME.split('/')[0]}/statuses/${sha}" `
        -Headers @{Authorization="Bearer \$env:GH"; "Accept"="application/vnd.github+json"} `
        -Body \$body
    """
  }
}

def commentOnPRIfAny(String msg) {
  if (!env.CHANGE_ID) return
  withCredentials([string(credentialsId: 'github-pat', variable: 'GH')]) {
    powershell """
      \$body = @{ body='${msg.replace("'", "''")}' } | ConvertTo-Json
      Invoke-RestMethod -Method POST `
        -Uri "https://api.github.com/repos/${env.GITHUB_OWNER}/${env.JOB_NAME.split('/')[0]}/issues/${env.CHANGE_ID}/comments" `
        -Headers @{Authorization="Bearer \$env:GH"; "Accept"="application/vnd.github+json"} `
        -Body \$body
    """
  }
}
