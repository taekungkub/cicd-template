# MVP Spec — Jenkins + ArgoCD + OpenBao

> **Scope:** minimal DevSecOps loop ที่รันได้จริงบน cluster เดียว
> **Goal:** push โค้ด → Jenkins build → ArgoCD deploy → secret มาจาก OpenBao (ไม่ hardcode)
> **Full vision:** ดู [`design-spec.md`](design-spec.md) — MVP นี้คือ subset ที่ทำก่อน

---

## 0. Definition of Done

1. ติดตั้ง ArgoCD + Jenkins + OpenBao + ESO บน cluster ด้วยขั้นตอนใน §4 ได้
2. push โค้ด → Jenkins build image + push → อัปเดต tag ใน `gitops/` → ArgoCD sync อัตโนมัติ
3. sample app อ่าน secret จาก OpenBao (ผ่าน ESO) ได้ โดยไม่มี plaintext ใน git
4. `scripts/smoke-test.sh` ผ่านทั้งหมด (§6)

**ตัดออกจาก MVP:** GitLab, SonarQube, Trivy, Kong, Entra SSO, OpenSearch, VPN, multi-env, HA

---

## 1. Prerequisites (สมมติมีแล้ว)

- Kubernetes cluster 1 ตัว — **kind / minikube / k3s ก็พอ** สำหรับเริ่ม
- `kubectl`, `helm`, `git` ในเครื่อง
- Git repo 1 ตัว (GitHub/GitLab ที่มีอยู่) แบ่งเป็น:
  - `app/` — โค้ด + Dockerfile + Jenkinsfile
  - `gitops/` — k8s manifests ที่ ArgoCD ดู (จะเป็นโฟลเดอร์เดียวกันหรือ repo แยกก็ได้)
- Container registry ที่ push ได้ (Docker Hub / GHCR / registry ใน cluster)

---

## 2. Components (MVP)

| Component | Version | ติดตั้งด้วย | บทบาท |
|-----------|---------|-----------|-------|
| ArgoCD | 2.13.x | Helm `argo/argo-cd` | CD / GitOps |
| Jenkins | LTS 2.462.x | Helm `jenkins/jenkins` | CI |
| OpenBao | 2.x | Helm `openbao/openbao` (**dev mode ก่อน**) | secret store |
| External Secrets Operator | 0.10.x | Helm `external-secrets/external-secrets` | สะพาน OpenBao → k8s Secret |

> **เริ่มง่าย:** OpenBao รัน dev mode (in-memory, auto-unseal, root token คงที่) เพื่อทดสอบ loop ก่อน — **ห้ามใช้ dev mode บน prod** (จะย้ายไป Raft HA + auto-unseal ในเฟสถัดไป)

---

## 3. Repo Layout (MVP — เล็กลงจาก full spec)

```
cicd-template/
├── docs/mvp-spec.md            # ไฟล์นี้
├── platform/
│   ├── argocd/
│   │   ├── install.md          # ขั้นตอนติดตั้ง
│   │   └── apps/sample-app.yaml # ArgoCD Application
│   ├── jenkins/
│   │   ├── values.yaml
│   │   └── casc.yaml           # Jenkins Config-as-Code (minimal)
│   ├── openbao/values.yaml     # dev mode
│   └── external-secrets/
│       ├── values.yaml
│       ├── secretstore.yaml    # ชี้ OpenBao
│       └── externalsecret.yaml # sync secret → namespace app
├── app/
│   ├── Dockerfile
│   └── Jenkinsfile
├── gitops/
│   └── sample-app/
│       ├── deployment.yaml     # image tag ถูก bump โดย pipeline
│       └── service.yaml
└── scripts/
    ├── bump-image.sh
    └── smoke-test.sh
```

---

## 4. Build Order (ทำตามลำดับ)

1. **ArgoCD**
   ```bash
   helm repo add argo https://argoproj.github.io/argo-helm
   helm install argocd argo/argo-cd -n argocd --create-namespace
   # เปิด UI: kubectl -n argocd port-forward svc/argocd-server 8080:443
   # รหัส admin เริ่มต้น: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
   ```

2. **OpenBao (dev mode)**
   ```bash
   helm repo add openbao https://openbao.github.io/openbao-helm
   helm install openbao openbao/openbao -n openbao --create-namespace \
     --set server.dev.enabled=true --set server.dev.devRootToken=root
   # เปิด kubernetes auth + เขียน secret ตัวอย่าง:
   #   bao auth enable kubernetes
   #   bao kv put secret/sample-app db_password=s3cr3t
   ```

3. **External Secrets Operator**
   ```bash
   helm repo add external-secrets https://charts.external-secrets.io
   helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
   ```
   แล้ว apply `secretstore.yaml` + `externalsecret.yaml` (§5.2)

4. **Jenkins**
   ```bash
   helm repo add jenkins https://charts.jenkins.io
   helm install jenkins jenkins/jenkins -n jenkins --create-namespace -f platform/jenkins/values.yaml
   ```
   ใช้ JCasC (`casc.yaml`) กำหนด: kubernetes cloud (ephemeral agent), seed job ชี้ `app/Jenkinsfile`

5. **เชื่อม loop** — apply `platform/argocd/apps/sample-app.yaml` ให้ ArgoCD ดู `gitops/sample-app/`, แล้วรัน pipeline ครั้งแรก

---

## 5. Concrete Manifests (ตัวอย่างที่ agent สร้างได้เลย)

### 5.1 ArgoCD Application — `platform/argocd/apps/sample-app.yaml`
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: sample-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: <YOUR_GIT_REPO_URL>
    targetRevision: main
    path: gitops/sample-app
  destination:
    server: https://kubernetes.default.svc
    namespace: sample-app
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [ CreateNamespace=true ]
```

### 5.2 OpenBao → k8s via ESO
```yaml
# secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata: { name: openbao, namespace: sample-app }
spec:
  provider:
    vault:                       # OpenBao ใช้ Vault API ได้
      server: "http://openbao.openbao.svc:8200"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "sample-app"
---
# externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: { name: sample-app-secrets, namespace: sample-app }
spec:
  refreshInterval: 1m
  secretStoreRef: { name: openbao, kind: SecretStore }
  target: { name: sample-app-secrets }   # จะได้ k8s Secret ชื่อนี้
  data:
    - secretKey: db_password
      remoteRef: { key: sample-app, property: db_password }
```

### 5.3 Jenkinsfile — `app/Jenkinsfile` (minimal)
```groovy
pipeline {
  agent { kubernetes { defaultContainer 'builder' } }   // ephemeral pod agent
  environment { REGISTRY = '<YOUR_REGISTRY>'; APP = 'sample-app' }
  stages {
    stage('Checkout') { steps { checkout scm } }
    stage('Build & Push') {
      steps {
        sh 'docker build -t $REGISTRY/$APP:$GIT_COMMIT app/'
        sh 'docker push $REGISTRY/$APP:$GIT_COMMIT'
      }
    }
    stage('Promote (GitOps)') {
      steps { sh './scripts/bump-image.sh gitops/sample-app/deployment.yaml $REGISTRY/$APP:$GIT_COMMIT' }
    }
  }
}
```

### 5.4 `scripts/bump-image.sh`
```bash
#!/usr/bin/env bash
set -euo pipefail
FILE="$1"; IMAGE="$2"
sed -i "s#image: .*#image: ${IMAGE}#" "$FILE"
git config user.email ci@local && git config user.name jenkins
git commit -am "ci: bump ${IMAGE}" && git push
# ArgoCD auto-sync จะเห็น commit นี้แล้ว deploy ต่อ
```

---

## 6. Smoke Test / Acceptance (`scripts/smoke-test.sh`)

- [ ] ArgoCD UI ขึ้น, login ด้วย admin ได้
- [ ] `bao kv get secret/sample-app` มีค่า และ ESO sync เป็น k8s Secret `sample-app-secrets` ใน namespace `sample-app`
- [ ] push commit → Jenkins build อัตโนมัติ (webhook หรือ poll)
- [ ] image ใหม่ถูก push เข้า registry ด้วย tag = git commit
- [ ] `gitops/sample-app/deployment.yaml` ถูก bump tag อัตโนมัติ
- [ ] ArgoCD sync แล้ว pod ใหม่รันด้วย image ใหม่ + mount secret จาก OpenBao
- [ ] `grep -r "password" gitops/` ไม่เจอ plaintext secret

---

## 7. เฟสถัดไป (เมื่อ MVP เดินได้)

1. OpenBao dev → **Raft HA + auto-unseal** (production-ready)
2. เพิ่ม **Trivy + SonarQube** เข้า Jenkins pipeline (security gate)
3. เพิ่ม **Kong** ingress + TLS (cert-manager)
4. เพิ่ม **Entra ID SSO** ให้ทุก UI
5. เพิ่ม **OpenSearch** logging
6. ย้าย SCM ไป **GitLab CE** + multi-env (dev/staging/prod)

> แต่ละเฟสมี component spec ละเอียดใน [`design-spec.md`](design-spec.md) §5 อยู่แล้ว
