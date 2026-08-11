# Bootstrap — Jenkins + ArgoCD + OpenBao (MVP)

รันตามลำดับนี้บน cluster เปล่า (kind/minikube/k3s ก็ได้). Spec เต็มดู [`docs/mvp-spec.md`](docs/mvp-spec.md)

## 0. ก่อนเริ่ม — แก้ placeholder 3 จุด
| ไฟล์ | แก้ |
|------|-----|
| `platform/argocd/apps/sample-app.yaml` | `<YOUR_GIT_REPO_URL>` = repo ที่มีโฟลเดอร์ `gitops/` |
| `app/Jenkinsfile` | `<YOUR_REGISTRY>` = registry ที่ push ได้ |
| `platform/jenkins/casc.yaml` | `<YOUR_GIT_REPO_URL>`, `<REGISTRY_USER/PASS>` |

## 1. ArgoCD (ตัว deploy)
```bash
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace
# UI:  kubectl -n argocd port-forward svc/argocd-server 8080:443
# pass: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

## 2. OpenBao (dev mode) + ตั้งค่า
```bash
helm repo add openbao https://openbao.github.io/openbao-helm && helm repo update
helm install openbao openbao/openbao -n openbao --create-namespace -f platform/openbao/values.yaml
kubectl -n openbao rollout status statefulset/openbao         # รอ Running
bash scripts/openbao-setup.sh                                 # สร้าง secret + role + policy
```

## 3. External Secrets Operator (สะพาน OpenBao → k8s)
```bash
helm repo add external-secrets https://charts.external-secrets.io && helm repo update
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace -f platform/external-secrets/values.yaml
kubectl create namespace sample-app --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f platform/external-secrets/secretstore.yaml
kubectl apply -f platform/external-secrets/externalsecret.yaml
# เช็ค: kubectl -n sample-app get secret sample-app-secrets   # ต้องโผล่ภายใน ~1 นาที
```

## 4. Jenkins (ตัว build)
```bash
helm repo add jenkins https://charts.jenkins.io && helm repo update
helm install jenkins jenkins/jenkins -n jenkins --create-namespace -f platform/jenkins/values.yaml
# UI:  kubectl -n jenkins port-forward svc/jenkins 8081:8080
# pass: kubectl -n jenkins get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d
```

## 5. เชื่อม loop — ให้ ArgoCD ดู sample app
```bash
kubectl apply -f platform/argocd/apps/sample-app.yaml
# ArgoCD จะ deploy gitops/sample-app/ ให้อัตโนมัติ
```

## 6. ทดสอบ loop เต็ม
1. แก้ไฟล์ใน `app/` แล้ว push
2. Jenkins job `sample-app` build → push image → `bump-image.sh` แก้ tag ใน `gitops/`
3. ArgoCD เห็น commit ใหม่ → sync → pod ใหม่ขึ้น
4. ตรวจผล:
```bash
bash scripts/smoke-test.sh
kubectl -n sample-app port-forward svc/sample-app 8888:80   # เปิด http://localhost:8888
```

---

## ลำดับความสำคัญ (ทำไมเรียงแบบนี้)
```
OpenBao + ESO   →  มีก่อน เพราะ app ต้องการ secret ตั้งแต่ deploy
ArgoCD          →  ตัวรับ desired state จาก Git
Jenkins         →  ตัวป้อน desired state (แก้ tag) เข้า Git
Git             →  จุดเชื่อมกลาง — Jenkins เขียน, ArgoCD อ่าน (ไม่คุยกันตรงๆ)
```

## ปัญหาที่เจอบ่อย
- **secret ไม่โผล่:** `kubectl -n sample-app describe externalsecret sample-app-secrets` → ดู error auth กับ OpenBao (มัก role/SA ไม่ตรง)
- **ArgoCD ไม่ sync:** เช็ค `repoURL` ถูกไหม + repo เป็น public หรือใส่ cred แล้ว
- **Jenkins push image ไม่ได้:** `registry-cred` ใน casc.yaml ยังเป็น placeholder
- **OpenBao restart แล้ว secret หาย:** ปกติของ dev mode — เฟสถัดไปย้ายเป็น Raft HA
