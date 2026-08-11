# Local Control Plane (docker compose) — minimal

รันแค่ **Jenkins + OpenBao** ในเครื่อง ใช้ **GitHub** เป็น repo. เน้น trigger ง่ายๆ ยังไม่มี registry/deploy.

## รันอะไรได้บ้าง

| Service | Port | ใช้ทำอะไร |
|---------|------|-----------|
| Jenkins | http://localhost:8081 | CI — trigger + build |
| OpenBao | http://localhost:8200 (token `root`) | secret store (dev) |

## 1. เริ่ม
```bash
cd compose
docker compose up -d
bash seed-openbao.sh                 # ใส่ secret ตัวอย่างเข้า OpenBao

# รหัส Jenkins admin ครั้งแรก:
docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
```
เปิด http://localhost:8081 → ใส่รหัสข้างบน → ติดตั้ง suggested plugins → สร้าง user

## 2. สร้าง Pipeline job ชี้ GitHub
ใน Jenkins UI:
1. **New Item** → ตั้งชื่อ `sample-app` → เลือก **Pipeline** → OK
2. หัวข้อ **Pipeline** เลือก **Pipeline script from SCM**
   - SCM: **Git**
   - Repository URL: `https://github.com/<you>/<repo>.git`
   - Branch: `*/main`
   - **Script Path:** `app/Jenkinsfile`
3. หัวข้อ **Build Triggers** → ติ๊ก **Poll SCM** → ใส่ `* * * * *` (เช็คทุก 1 นาที)
   > หรือกด **Build Now** ทดสอบด้วยมือก็ได้
4. Save → push โค้ดที่ GitHub → Jenkins จะเห็นแล้วรัน pipeline (checkout → build → อ่าน secret จาก OpenBao)

## 3. อยาก trigger แบบ real-time (push แล้ววิ่งทันที)?
Jenkins รันที่ `localhost` GitHub ยิง webhook เข้ามาตรงๆ ไม่ได้ ต้องมี public URL:
```bash
# ตัวอย่างด้วย ngrok (ทางที่ง่ายสุด)
ngrok http 8081
# เอา URL ที่ได้ไปใส่ GitHub repo → Settings → Webhooks → Payload URL: https://xxxx.ngrok.io/github-webhook/
```
ถ้ายังไม่อยากยุ่ง — **Poll SCM ทุก 1 นาที ก็พอสำหรับทดลอง** (แค่ช้ากว่านิดหน่อย)

---

## ⚠️ ArgoCD ไม่อยู่ใน compose — ทำไม

ArgoCD **ต้องมี Kubernetes** เป็นเป้าหมาย deploy จึงรันใน compose ไม่ได้.
ตอนนี้เราตัด deploy ออกก่อน (แค่ trigger + build). เมื่อพร้อมค่อยเติม k8s ด้วย **k3d**:
```bash
k3d cluster create cicd
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm install argocd argo/argo-cd -n argocd --create-namespace
kubectl apply -f ../platform/argocd/apps/sample-app.yaml
```

## ภาพรวมตอนนี้
```
GitHub (repo)  --push-->  Jenkins (compose)  --build + อ่าน secret-->  OpenBao (compose)
                                   │
                                   └── (เฟสหลัง) push image + ArgoCD deploy ลง k3d
```
