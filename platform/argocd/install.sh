#!/usr/bin/env bash
# platform/argocd/install.sh — ติดตั้ง/อัปเดต ArgoCD บน cluster ปัจจุบัน (idempotent)
#
#   bash platform/argocd/install.sh
#
# รันซ้ำได้เสมอ: kubectl apply เป็น declarative — ของที่มีอยู่แล้วจะขึ้น "unchanged"
# ไม่สร้างซ้ำ ไม่ restart pod. ใช้สคริปต์นี้ทั้งตอนติดตั้งครั้งแรกและตอนอัปเดต config
#
# ⚠️ config นี้ตั้งใจให้ใช้กับ cluster บนเครื่องตัวเองเท่านั้น (docker-desktop / k3d / kind)
#    - server.insecure=true  → UI เป็น http ธรรมดา รหัสผ่านวิ่งแบบ plain text
#    - NodePort              → เปิด port บนเครื่องถาวร
#    ห้ามใช้กับ cluster ที่คนอื่นเข้าถึงได้หรือเข้าถึงจากอินเทอร์เน็ต — ที่นั่นต้องเป็น
#    https + cert จริง + จำกัดการเข้าถึงเสมอ (ArgoCD UI คุม deploy ได้ทั้งระบบ)

set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-v3.5.1}"
NAMESPACE="argocd"
NODEPORT="${ARGOCD_NODEPORT:-30080}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "▶ cluster ปลายทาง: $(kubectl config current-context)"
echo "▶ ArgoCD version : ${ARGOCD_VERSION}"
echo

# ── 1. namespace ─────────────────────────────────────────────────────────────
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# ── 2. ตัว ArgoCD เอง ────────────────────────────────────────────────────────
# --server-side: กัน error "metadata.annotations: Too long" ที่ CRD ใหญ่ๆ ชนเวลา
# apply แบบ client-side ซ้ำ (annotation last-applied-configuration ยาวเกิน 256KB)
echo "▶ apply manifest ArgoCD..."
kubectl apply -n "${NAMESPACE}" --server-side --force-conflicts \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

# ── 3. เปิด UI แบบ http (ไม่ต้องกดข้ามหน้าเตือน cert) ────────────────────────
# argocd-server อ่านค่านี้ตอน start → ต้อง restart deployment ถ้าค่าเปลี่ยน
echo "▶ ตั้ง server.insecure=true (UI เป็น http — local เท่านั้น)"
kubectl -n "${NAMESPACE}" patch configmap argocd-cmd-params-cm \
  --type merge -p '{"data":{"server.insecure":"true"}}'

# ── 4. เปิดทางเข้าจากเครื่อง: ClusterIP → NodePort ───────────────────────────
# ⚠️ Docker Desktop k8s รุ่นใหม่รัน node ใน VM แยก (แบบ kind) → NodePort "ไม่" ทะลุออก
#    localhost และไม่มี LoadBalancer provider — ทางเข้าจริงบนเครื่องนี้คือ port-forward
#    ที่ open.sh เปิดให้ (background). patch นี้เก็บไว้เพราะบน k3d/kind ที่ map port ไว้
#    NodePort จะใช้ได้ทันทีโดยไม่ต้อง port-forward
echo "▶ patch service argocd-server → NodePort ${NODEPORT}"
kubectl -n "${NAMESPACE}" patch svc argocd-server --type merge -p "$(cat <<EOF
{"spec":{"type":"NodePort","ports":[
  {"name":"http","port":80,"targetPort":8080,"nodePort":${NODEPORT}},
  {"name":"https","port":443,"targetPort":8080}
]}}
EOF
)"

# restart ให้ config ข้อ 3 มีผล (no-op ถ้าค่าไม่เปลี่ยนก็ยัง rollout ใหม่รอบเดียว เร็ว)
kubectl -n "${NAMESPACE}" rollout restart deployment argocd-server

echo "▶ รอ ArgoCD พร้อมใช้งาน..."
kubectl -n "${NAMESPACE}" rollout status deployment argocd-server --timeout=180s
kubectl -n "${NAMESPACE}" rollout status deployment argocd-repo-server --timeout=180s

# ── 5. Application ทั้งหมดใน apps/ ───────────────────────────────────────────
# ⚠️ ถ้าจะแค่ "เพิ่ม/แก้ app" ใช้ apply-apps.sh แทน — สคริปต์นี้ restart argocd-server ด้วย
#    (port-forward ที่เปิดไว้จะตาย ต้องรัน open.sh ใหม่) ซึ่งไม่จำเป็นสำหรับการเพิ่ม app
if compgen -G "${HERE}/apps/*.yaml" > /dev/null; then
  echo "▶ apply Application ใน apps/"
  kubectl apply -f "${HERE}/apps/"
else
  echo "▶ ไม่มีไฟล์ใน apps/ — ข้าม"
fi

echo
echo "✅ เสร็จแล้ว"
bash "${HERE}/open.sh"
