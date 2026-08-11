#!/usr/bin/env bash
# ใส่ secret ตัวอย่างเข้า OpenBao (compose dev mode)
# รันหลัง docker compose up:  bash compose/seed-openbao.sh
set -euo pipefail

# ใช้ bao CLI ภายใน container (ไม่ต้องติดตั้งในเครื่อง)
bao() { docker exec -e BAO_ADDR=http://127.0.0.1:8200 -e BAO_TOKEN=root openbao bao "$@"; }

echo "==> เปิด KV v2 (dev mode มัก mount secret/ ให้แล้ว — สั่งซ้ำได้ไม่พัง)"
bao secrets enable -path=secret kv-v2 2>/dev/null || true

echo "==> เขียน secret ตัวอย่าง"
bao kv put secret/sample-app db_password=s3cr3t-from-openbao

echo "==> อ่านกลับเพื่อยืนยัน"
bao kv get secret/sample-app

echo "✅ OpenBao (compose) พร้อมใช้งาน — token: root, addr: http://localhost:8200"
