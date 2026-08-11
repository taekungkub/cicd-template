#!/usr/bin/env bash
# ตรวจว่า MVP loop เดินครบไหม
set -uo pipefail
ok(){ echo "✅ $1"; } ; bad(){ echo "❌ $1"; FAIL=1; }
FAIL=0

echo "== 1) ArgoCD, Jenkins, OpenBao, ESO ขึ้นครบ =="
for ns in argocd jenkins openbao external-secrets; do
  kubectl get ns "$ns" >/dev/null 2>&1 && ok "namespace $ns" || bad "namespace $ns หาย"
done

echo "== 2) ESO sync secret จาก OpenBao =="
if kubectl -n sample-app get secret sample-app-secrets >/dev/null 2>&1; then
  ok "k8s Secret sample-app-secrets ถูกสร้างโดย ESO"
else
  bad "ยังไม่มี secret (เช็ค ExternalSecret: kubectl -n sample-app describe externalsecret sample-app-secrets)"
fi

echo "== 3) ArgoCD app synced =="
kubectl -n argocd get application sample-app >/dev/null 2>&1 \
  && ok "ArgoCD Application sample-app มีอยู่" \
  || bad "ยังไม่ได้ apply platform/argocd/apps/sample-app.yaml"

echo "== 4) app pod รันอยู่ =="
READY=$(kubectl -n sample-app get deploy sample-app -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
[ "${READY:-0}" -ge 1 ] && ok "sample-app ready ($READY replica)" || bad "sample-app ยังไม่ ready"

echo "== 5) ไม่มี plaintext secret ใน gitops/ =="
if grep -rniE "password:\s*\S" gitops/ >/dev/null 2>&1; then
  bad "เจอ plaintext ที่ดูเหมือน secret ใน gitops/"
else
  ok "ไม่มี plaintext secret ใน gitops/"
fi

echo "-------------------------------------------"
[ "$FAIL" -eq 0 ] && echo "🎉 ผ่านทั้งหมด" || echo "⚠️ มีรายการไม่ผ่าน ดูข้างบน"
exit "$FAIL"
