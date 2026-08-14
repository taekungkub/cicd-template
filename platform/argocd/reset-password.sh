#!/usr/bin/env bash
# platform/argocd/reset-password.sh — รีเซ็ตรหัสผ่าน admin ของ ArgoCD
#
#   bash platform/argocd/reset-password.sh
#
# ใช้เมื่อ: login แล้วขึ้น "Invalid username or password" ทั้งที่ใช้รหัสจาก open.sh
#
# ทำไมเกิด: ArgoCD เก็บ hash รหัสไว้ที่ secret `argocd-secret` (field admin.password)
# แต่รหัส plain text ที่เอาไปกรอกอยู่ที่ secret คนละตัว (`argocd-initial-admin-secret`)
# ถ้า 2 ตัวนี้มาจากคนละรอบติดตั้ง (install ล้มกลางทาง / apply ทับ) → hash ไม่ตรงกับรหัสที่โชว์
# เช็คได้จาก timestamp 2 ตัวนี้ ถ้าต่างกันคือเพี้ยน:
#   kubectl -n argocd get secret argocd-secret -o jsonpath='{.data.admin\.passwordMtime}' | base64 -d
#   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.metadata.creationTimestamp}'
#
# วิธีแก้: ล้าง field รหัสทิ้งแล้ว restart → argocd-server สุ่มรหัสใหม่
# พร้อมเขียน argocd-initial-admin-secret ให้ตรงกันในรอบเดียว
#
# ⚠️ รหัส admin เดิมถูกทิ้ง (รวมถึงรหัสที่ตั้งเองใน UI) — Application/workload ที่ deploy ไว้ไม่กระทบ

set -euo pipefail

NAMESPACE="argocd"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! kubectl -n "${NAMESPACE}" get deploy argocd-server >/dev/null 2>&1; then
  echo "❌ ยังไม่มี ArgoCD ใน cluster นี้ — ติดตั้งก่อน: bash platform/argocd/install.sh"
  exit 1
fi

echo "⚠️  กำลังจะรีเซ็ตรหัสผ่าน admin ของ ArgoCD บน cluster:"
echo "    $(kubectl config current-context)"
echo "    รหัสเดิมจะใช้ไม่ได้อีก (รวมรหัสที่ตั้งเองใน UI)"
echo
read -r -p "พิมพ์ 'yes' เพื่อยืนยัน: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "ยกเลิก"
  exit 1
fi

# ลบตัวเก่าทิ้งก่อน ไม่งั้น argocd-server เห็นว่ามีอยู่แล้วและไม่เขียนรหัสใหม่ลงไป
kubectl -n "${NAMESPACE}" delete secret argocd-initial-admin-secret --ignore-not-found

# ล้าง hash + mtime → ตอน start ใหม่ argocd-server ถือว่า "ยังไม่เคยตั้งรหัส"
kubectl -n "${NAMESPACE}" patch secret argocd-secret \
  -p '{"data":{"admin.password":null,"admin.passwordMtime":null}}'

kubectl -n "${NAMESPACE}" rollout restart deployment argocd-server
kubectl -n "${NAMESPACE}" rollout status deployment argocd-server --timeout=180s

# port-forward เดิมตายไปพร้อม pod เก่า → เปิดใหม่ให้เลย
bash "${HERE}/open.sh" --stop >/dev/null 2>&1 || true

echo
echo "✅ รีเซ็ตเรียบร้อย — รหัสใหม่:"
bash "${HERE}/open.sh"
