#!/usr/bin/env bash
# ตั้งค่า OpenBao (dev mode) ให้ ESO ดึง secret ได้ผ่าน Kubernetes auth
# รันหลังจาก helm install openbao แล้ว (pod openbao-0 ต้อง Running)
set -euo pipefail

NS_BAO="openbao"
POD="openbao-0"
ROLE="sample-app"          # role สำหรับ ESO SA
APP_NS="sample-app"
ESO_SA="eso-sample-app"

# รันคำสั่ง bao ภายใน pod (dev mode: root token = "root")
bao() { kubectl -n "$NS_BAO" exec -i "$POD" -- sh -c "VAULT_TOKEN=root BAO_TOKEN=root $*"; }

echo "==> 1) เขียน secret ตัวอย่าง"
bao "bao kv put secret/sample-app db_password=s3cr3t-from-openbao"

echo "==> 2) เปิด kubernetes auth"
bao "bao auth enable kubernetes || true"
bao "bao write auth/kubernetes/config \
      kubernetes_host=https://\$KUBERNETES_PORT_443_TCP_ADDR:443"

echo "==> 3) policy อ่าน secret/sample-app ได้อย่างเดียว"
bao "echo 'path \"secret/data/sample-app\" { capabilities = [\"read\"] }' | bao policy write sample-app-ro -"

echo "==> 4) ผูก role -> SA (${APP_NS}/${ESO_SA})"
bao "bao write auth/kubernetes/role/${ROLE} \
      bound_service_account_names=${ESO_SA} \
      bound_service_account_namespaces=${APP_NS} \
      policies=sample-app-ro ttl=1h"

echo "✅ OpenBao พร้อม — ต่อไป apply secretstore.yaml + externalsecret.yaml"
