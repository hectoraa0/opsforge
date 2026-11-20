#!/usr/bin/env bash
# Ephemeral GitHub Actions integration test. Never targets the user's local cluster.
set -Eeuo pipefail

context='kind-opsforge'
namespace='opsforge'
forward_pid=''

cleanup() {
  local code=$?
  if (( code != 0 )); then
    echo 'CI diagnosis: cluster resources' >&2
    kubectl --context "$context" -n "$namespace" get pods,services,pvc -o wide || true
    kubectl --context "$context" -n "$namespace" describe pods || true
    kubectl --context "$context" -n "$namespace" logs deployment/opsforge-api --all-containers=true --tail=100 || true
    kubectl --context "$context" -n "$namespace" logs statefulset/opsforge-db --tail=60 || true
    [[ ! -f /tmp/opsforge-forward.log ]] || tail -60 /tmp/opsforge-forward.log || true
  fi
  if [[ -n "$forward_pid" ]]; then
    kill "$forward_pid" 2>/dev/null || true
    wait "$forward_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT

kind create cluster --name opsforge --wait 5m
kubectl --context "$context" get nodes

docker build --tag opsforge-api:kind .
kind load docker-image opsforge-api:kind --name opsforge

kubectl --context "$context" apply -f k8s/namespace.yaml

# Disposable CI-only credentials: not real passwords, never reused in any real environment.
ci_password='ci-only-disposable-password-123'
ci_url="postgresql+psycopg://opsforge:${ci_password}@opsforge-db:5432/opsforge"
kubectl --context "$context" -n "$namespace" create secret generic opsforge-db \
  --from-literal="password=${ci_password}" \
  --from-literal="database_url=${ci_url}"

kubectl --context "$context" apply -f k8s/postgres.yaml
kubectl --context "$context" -n "$namespace" rollout status statefulset/opsforge-db --timeout=180s
kubectl --context "$context" apply -f k8s/api.yaml
kubectl --context "$context" -n "$namespace" rollout status deployment/opsforge-api --timeout=180s
kubectl --context "$context" -n "$namespace" wait pod \
  -l app.kubernetes.io/name=opsforge-api --for=condition=Ready --timeout=180s

start_forward() {
  kubectl --context "$context" -n "$namespace" \
    port-forward svc/opsforge-api 8000:8000 >/tmp/opsforge-forward.log 2>&1 &
  forward_pid=$!
}
stop_forward() {
  if [[ -n "$forward_pid" ]]; then
    kill "$forward_pid" 2>/dev/null || true
    wait "$forward_pid" 2>/dev/null || true
    forward_pid=''
  fi
}

start_forward
# The smoke test retries readiness, then creates, updates, and reads an incident from PostgreSQL.
python scripts/smoke_test.py

saved_id=$(python - <<'PY'
import json
from urllib.request import urlopen
with urlopen('http://127.0.0.1:8000/api/v1/incidents', timeout=5) as response:
    incidents = json.load(response)
matched = [row['id'] for row in incidents if row['title'] == 'Smoke test incident' and row['status'] == 'resolved']
assert matched, 'Expected an incident created by smoke_test.py'
print(matched[0])
PY
)

old_pod=$(kubectl --context "$context" -n "$namespace" get pods \
  -l app.kubernetes.io/name=opsforge-api -o jsonpath='{.items[0].metadata.name}')
[[ -n "$old_pod" ]] || { echo 'No API Pod found' >&2; exit 1; }

# Deleting the API Pod is safe in the disposable CI cluster; the Deployment should recreate it.
stop_forward
kubectl --context "$context" -n "$namespace" delete pod "$old_pod" --wait=true
kubectl --context "$context" -n "$namespace" rollout status deployment/opsforge-api --timeout=180s
kubectl --context "$context" -n "$namespace" wait pod \
  -l app.kubernetes.io/name=opsforge-api --for=condition=Ready --timeout=180s
new_pod=$(kubectl --context "$context" -n "$namespace" get pods \
  -l app.kubernetes.io/name=opsforge-api -o jsonpath='{.items[0].metadata.name}')
[[ -n "$new_pod" && "$new_pod" != "$old_pod" ]] || {
  echo "Expected a replacement API Pod. Old=$old_pod New=$new_pod" >&2
  exit 1
}

start_forward
python - "$saved_id" <<'PY'
import json
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import urlopen

incident_id = sys.argv[1]
url = f'http://127.0.0.1:8000/api/v1/incidents/{incident_id}'
for attempt in range(60):
    try:
        with urlopen(url, timeout=4) as response:
            incident = json.load(response)
        assert incident['status'] == 'resolved', incident
        assert incident['title'] == 'Smoke test incident', incident
        print('PASS: API Pod recreated and PostgreSQL incident survived the restart')
        break
    except (OSError, URLError, HTTPError):
        time.sleep(2)
else:
    raise SystemExit('API did not recover after Pod replacement')
PY

kubectl --context "$context" -n "$namespace" get pods,services,pvc
