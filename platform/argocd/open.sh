#!/usr/bin/env bash
# platform/argocd/open.sh — เปิดทางเข้า ArgoCD UI + บอก user/password
#
#   bash platform/argocd/open.sh          # เปิด port-forward (background) + โชว์ URL/รหัส
#   bash platform/argocd/open.sh --stop   # ปิด port-forward
#
# ทำไมต้อง port-forward: Docker Desktop k8s รุ่นใหม่รัน node ใน VM แยก (แบบ kind)
# → NodePort ไม่ทะลุออก localhost และไม่มี LoadBalancer provider (EXTERNAL-IP ค้าง <pending>)
# สคริปต์นี้เลยรัน port-forward แบบ background ให้ครั้งเดียว ไม่ต้องเปิด terminal ค้าง
# (ถ้าย้ายไป k3d วันหลัง NodePort ที่ install.sh patch ไว้จะใช้ได้ทันที)

set -euo pipefail

NAMESPACE="argocd"
PORT="${ARGOCD_PORT:-30080}"
PIDFILE="/tmp/argocd-port-forward.pid"

stop_forward() {
  if [[ -f "${PIDFILE}" ]] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
    kill "$(cat "${PIDFILE}")" 2>/dev/null || true
    rm -f "${PIDFILE}"
    return 0
  fi
  rm -f "${PIDFILE}"
  return 1
}

if [[ "${1:-}" == "--stop" ]]; then
  if stop_forward; then echo "✅ ปิด port-forward แล้ว"; else echo "ไม่มี port-forward ที่รันอยู่"; fi
  exit 0
fi

if ! kubectl -n "${NAMESPACE}" get deploy argocd-server >/dev/null 2>&1; then
  echo "❌ ยังไม่มี ArgoCD ใน cluster นี้ — ติดตั้งก่อน:"
  echo "   bash platform/argocd/install.sh"
  exit 1
fi

# ── เปิด port-forward ถ้ายังไม่มีตัวที่รันอยู่ ────────────────────────────────
if [[ -f "${PIDFILE}" ]] && kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
  echo "▶ port-forward รันอยู่แล้ว (pid $(cat "${PIDFILE}"))"
else
  rm -f "${PIDFILE}"
  nohup kubectl -n "${NAMESPACE}" port-forward svc/argocd-server "${PORT}:80" \
    > /tmp/argocd-port-forward.log 2>&1 &
  echo $! > "${PIDFILE}"
  sleep 2
  if ! kill -0 "$(cat "${PIDFILE}")" 2>/dev/null; then
    echo "❌ port-forward ล้มเหลว — ดู log: /tmp/argocd-port-forward.log"
    rm -f "${PIDFILE}"
    exit 1
  fi
  echo "▶ เปิด port-forward แล้ว (pid $(cat "${PIDFILE}")) — ปิดด้วย: bash platform/argocd/open.sh --stop"
fi

echo
echo "┌─ ArgoCD ────────────────────────────────────────────"
echo "│ URL      : http://localhost:${PORT}"
echo "│ Username : admin"

# secret นี้ ArgoCD สร้างตอนติดตั้ง และ "ลบทิ้งเอง" เมื่อเปลี่ยนรหัสผ่านครั้งแรกใน UI
PASSWORD="$(kubectl -n "${NAMESPACE}" get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || true)"

if [[ -n "${PASSWORD}" ]]; then
  echo "│ Password : ${PASSWORD}"
else
  echo "│ Password : (เปลี่ยนไปแล้ว — secret argocd-initial-admin-secret ถูกลบ)"
  echo "│            ลืมรหัส? ล้าง field รหัสผ่านแล้วรัน install.sh ซ้ำ (ได้รหัสสุ่มใหม่):"
  echo "│            kubectl -n argocd patch secret argocd-secret -p '{\"data\":{\"admin.password\":null,\"admin.passwordMtime\":null}}'"
fi

echo "└─────────────────────────────────────────────────────"
echo
echo "Application ตอนนี้:"
kubectl -n "${NAMESPACE}" get applications.argoproj.io 2>/dev/null || echo "  (ยังไม่มี)"
