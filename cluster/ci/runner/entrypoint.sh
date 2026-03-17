#!/bin/bash
set -e

# PAT로 등록 토큰 자동 생성
if [ -n "${GITHUB_PAT}" ] && [ -n "${RUNNER_REPOSITORY_URL}" ]; then
  REPO_PATH=$(echo "${RUNNER_REPOSITORY_URL}" | sed 's|https://github.com/||')
  REG_TOKEN=$(curl -s -X POST \
    -H "Authorization: token ${GITHUB_PAT}" \
    -H "Accept: application/vnd.github.v3+json" \
    "https://api.github.com/repos/${REPO_PATH}/actions/runners/registration-token" \
    | grep -o '"token":"[^"]*"' | cut -d'"' -f4)

  if [ -z "${REG_TOKEN}" ]; then
    echo "ERROR: Failed to get registration token. Check GITHUB_PAT and RUNNER_REPOSITORY_URL."
    exit 1
  fi

  # 기존 등록 정리 (재시작 시)
  /home/runner/config.sh remove --token "${REG_TOKEN}" 2>/dev/null || true

  # Runner 등록
  /home/runner/config.sh \
    --url "${RUNNER_REPOSITORY_URL}" \
    --token "${REG_TOKEN}" \
    --name "${RUNNER_NAME:-kloud-runner}" \
    --labels "${RUNNER_LABELS:-kloud,self-hosted,linux,amd64}" \
    --work "${RUNNER_WORKDIR:-/tmp/runner}" \
    --replace \
    --unattended
fi

# Runner 실행
exec /home/runner/run.sh
