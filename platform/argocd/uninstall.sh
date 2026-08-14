#!/usr/bin/env bash
# platform/argocd/uninstall.sh — ถอน ArgoCD ออกจาก cluster
#
#   bash platform/argocd/uninstall.sh
#
# ลบ namespace argocd ทั้งก้อน (ตัว ArgoCD + Application CR + รหัสผ่าน admin)
# สร้างคืนได้ด้วย install.sh — แต่รหัสผ่าน admin จะเป็นค่าสุ่มใหม่
#
# หมายเหตุ: app ที่ ArgoCD deploy ไว้ (เช่น namespace sample-app) จะ "ไม่" ถูกลบ
# เพราะอยู่คนละ namespace — ถ้าอยากลบด้วยต้อง kubectl delete ns เอง

set -euo pipefail

NAMESPACE="argocd"

echo "⚠️  กำลังจะลบ namespace '${NAMESPACE}' ทั้งหมดออกจาก cluster:"
echo "    $(kubectl config current-context)"
echo
read -r -p "พิมพ์ 'yes' เพื่อยืนยัน: " CONFIRM
if [[ "${CONFIRM}" != "yes" ]]; then
  echo "ยกเลิก"
  exit 1
fi

# ลบ CRD ด้วย — ไม่งั้น Application/AppProject CRD ค้างอยู่ระดับ cluster
kubectl delete namespace "${NAMESPACE}" --ignore-not-found
kubectl delete crd applications.argoproj.io applicationsets.argoproj.io \
  appprojects.argoproj.io --ignore-not-found

echo "✅ ถอนเรียบร้อย — สร้างคืนด้วย: bash platform/argocd/install.sh"
