#!/usr/bin/env bash
# platform/argocd/apply-apps.sh — ลงทะเบียน Application ทั้งหมดใน apps/ เข้า ArgoCD
#
#   bash platform/argocd/apply-apps.sh
#
# ใช้ตอน "เพิ่ม/แก้ app" อย่างเดียว — ไม่แตะตัว ArgoCD เลย
#   → ไม่ restart argocd-server, port-forward ที่เปิดไว้ไม่ตาย
# (install.sh ก็ apply apps/ ให้เหมือนกัน แต่มัน restart server ด้วย ซึ่งแพงเกินไปถ้าจะแค่เพิ่ม app)
#
# วิธีเพิ่ม app ใหม่:
#   1. สร้างไฟล์ Application ใน apps/ (ก๊อป sample-app.yaml เป็นแบบ แล้วแก้ name/path/namespace)
#   2. bash platform/argocd/apply-apps.sh
#
# รันซ้ำได้เสมอ — ของเดิมขึ้น "unchanged", ของใหม่ขึ้น "created"

set -euo pipefail

NAMESPACE="argocd"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! kubectl -n "${NAMESPACE}" get deploy argocd-server >/dev/null 2>&1; then
  echo "❌ ยังไม่มี ArgoCD ใน cluster นี้ — ติดตั้งก่อน: bash platform/argocd/install.sh"
  exit 1
fi

if ! compgen -G "${HERE}/apps/*.yaml" > /dev/null; then
  echo "❌ ไม่มีไฟล์ .yaml ใน apps/ — ยังไม่มีอะไรให้ลงทะเบียน"
  exit 1
fi

echo "▶ cluster ปลายทาง: $(kubectl config current-context)"
kubectl apply -f "${HERE}/apps/"

echo
echo "Application ตอนนี้:"
kubectl -n "${NAMESPACE}" get applications.argoproj.io
echo
echo "> app ใหม่จะขึ้น OutOfSync/Progressing สักครู่ก่อนเป็น Synced/Healthy — ดูรายละเอียดที่ UI (open.sh)"
