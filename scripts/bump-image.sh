#!/usr/bin/env bash
# แก้ image tag ใน manifest แล้ว commit+push -> ArgoCD auto-sync จะ deploy ต่อ
set -euo pipefail

FILE="$1"     # เช่น gitops/sample-app/deployment.yaml
IMAGE="$2"    # เช่น docker.io/user/sample-app:<commit>

sed -i "s#image: .*#image: ${IMAGE}#" "$FILE"

git config user.email "ci@cicd-template.local"
git config user.name  "jenkins-ci"
git add "$FILE"
git commit -m "ci: deploy ${IMAGE}"
git push

echo "✅ bumped ${FILE} -> ${IMAGE} (ArgoCD จะ sync ให้)"
