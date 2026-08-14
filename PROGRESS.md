# Progress Log

> บันทึกความคืบหน้า เปิดอ่านตอนกลับมาทำต่อ

---

## 2026-08-11 — MVP loop (Jenkins + OpenBao) ทำงานได้แล้ว ✅

### สิ่งที่ทำเสร็จวันนี้
- ตั้ง **docker compose** รัน Jenkins + OpenBao ในเครื่อง (`compose/docker-compose.yml`)
- CI loop เดินครบ: **GitHub push → Jenkins (poll) → Checkout → Build → ดึง secret จาก OpenBao → SUCCESS** (build #5)
- อัปเกรดการดึง secret เป็นแบบปลอดภัย: ใช้ **HashiCorp Vault plugin** + `withVault` → secret เข้ามาเป็น env `$DB_PASSWORD` (masked ใน log, token ไม่ hardcode)

### ⭐ เป้าหมายหลักของ repo นี้ (อย่าลืม)
**นี่คือ "template กลาง" ที่ repo อื่นจะดึงไปใช้** — ไม่ใช่ pipeline ของแอปเดียว
→ `app/Jenkinsfile` ตอนนี้เป็นแค่ **ตัวอย่างพิสูจน์ loop** ยังไม่ใช่ของจริงสำหรับ reuse

### วิธีเข้าใช้งาน (ทุกอย่างรันอยู่ใน Docker)
| Service | URL | auth |
|---|---|---|
| Jenkins | http://localhost:9090 | admin (รหัสที่ตั้งไว้ตอน setup) |
| OpenBao UI | http://localhost:18200 | Method: Token, Token: `root` |

- Jenkins job: `sample-app` (Pipeline from SCM, Script Path `app/Jenkinsfile`, poll `* * * * *`)
- credential ใน Jenkins: `openbao-token` (kind = Vault Token Credential = `root`)
- secret ตัวอย่างใน OpenBao: `secret/sample-app` → `db_password=s3cr3t-from-openbao`

### วิธีกลับมาทำต่อ (ถ้า container ถูกปิด)
```bash
cd D:/workshop/cicd/cicd-template/compose
docker compose up -d
bash seed-openbao.sh          # dev mode เก็บใน memory — ปิดแล้ว secret หาย ต้อง seed ใหม่
```
> Vault plugin + credential ถูกเก็บใน docker volume `jenkins_home` — ไม่หายตอน restart (หายเฉพาะถ้า `docker compose down -v`)

### ⚠️ Gotchas ที่เจอมาแล้ว (กันเสียเวลาซ้ำ)
- Windows จอง host port 8081/8200 → remap เป็น **9090** (Jenkins), **18200** (OpenBao)
- Jenkins อ่าน Jenkinsfile **จาก GitHub** ไม่ใช่เครื่อง → แก้แล้วต้อง `git push` ก่อน build
- Script Path ต้องเป็น `app/Jenkinsfile` (ไม่ใช่ default `Jenkinsfile`)
- OpenBao image ต้อง `2.6.1` (มี UI) — `2.0` ไม่มี UI
- `vaultUrl` ใน Jenkinsfile ใช้ `http://openbao:8200` (ชื่อ service ใน network) ไม่ใช่ `localhost:18200`
- Git Bash: ใส่ `MSYS_NO_PATHCONV=1` ก่อน `docker exec ... <absolute path>`

---

## 2026-08-12 — Refactor เป็น Jenkins Shared Library ✅ (code เสร็จ, รอ push เพื่อทดสอบ)

### สิ่งที่ทำวันนี้
- สร้าง **Shared Library entrypoint** `vars/cicdPipeline.groovy` — ย้าย logic (checkout/build/withVault) มา parameterize
  ค่า config: `app`, `vaultPath` (default `secret/<app>`), `vaultUrl` (default `http://openbao:8200`),
  `vaultCred` (default `openbao-token`), `secrets` (list ของ envVar↔vaultKey), `poll`, `engineVersion`
- แปลง `app/Jenkinsfile` → เหลือ consumer แบบไม่กี่บรรทัด (`@Library('cicd-template@main') _` + `cicdPipeline(...)`)
- ทำ Global Pipeline Library ให้ **reproducible**: `compose/jenkins-init/configure-shared-library.groovy`
  (init.groovy.d, idempotent) ลงทะเบียน library `cicd-template` ชี้ GitHub repo อัตโนมัติตอน Jenkins startup
  → mount ใน `docker-compose.yml` (`./jenkins-init:/var/jenkins_home/init.groovy.d:ro`)
- recreate container jenkins → init script รันผ่าน (log: `[init] ✅ ลงทะเบียน Shared Library 'cicd-template'`)

### ⏭️ ค้างอยู่ (ทำต่อทันที)
- **ต้อง `git push` main** ก่อน ถึงจะทดสอบได้ — Jenkins ดึงทั้ง Jenkinsfile และ library จาก GitHub@main
  (ทั้ง `vars/cicdPipeline.groovy` และ `app/Jenkinsfile` ใหม่ยังอยู่แค่ในเครื่อง)
- หลัง push → trigger build `sample-app` → คาดว่าผ่านเหมือน build #5 แต่คราวนี้ logic มาจาก library กลาง
- ถ้าจะพิสูจน์เต็มรูปแบบ: สร้าง repo consumer แยกจริง (คนละ GitHub repo) ที่มีแค่ Jenkinsfile 3 บรรทัด

---

## 2026-08-12 — เปลี่ยนทิศ template กลาง: แชร์แค่ "ดึง env" ไม่ครอบทั้ง pipeline ✅

### เหตุผล
`cicdPipeline` (ครอบ pipeline ทั้งหมด) บังคับทุก repo ใช้ stage `Build` เหมือนกัน → ไม่เข้ากับความจริง
ที่แต่ละ repo คนละภาษา แต่ละคนควร build/test/deploy เอง สิ่งเดียวที่ต้องแชร์คือ **การดึง env จาก OpenBao**

### สิ่งที่ทำ
- **ลบ** `vars/cicdPipeline.groovy` (all-in-one เดิม) ทิ้ง — เหลือ entrypoint เดียว
- **เพิ่ม** `vars/withOpenBao.groovy` — shared step ตัวเดียว ซ่อน config OpenBao
  (`vaultUrl=http://openbao:8200`, `vaultCred=openbao-token`, engine v2) ห่อ `withVault` ให้ repo ไม่ต้องเขียนซ้ำ
- **`app/Jenkinsfile`** กลับเป็น **pipeline ปกติเต็มรูป** (repo เป็นเจ้าของ Build/Test/Deploy)
  ใช้ `withOpenBao(app:..., secrets:[...]) { ... }` เฉพาะช่วงที่ต้องใช้ secret

### วิธี consumer ใช้ (คง syntax Jenkinsfile เดิมของแต่ละภาษา)
```groovy
@Library('cicd-template@main') _
pipeline {
  agent any
  stages {
    stage('Build')  { steps { sh 'npm ci && npm run build' } }   // repo เขียนเอง
    stage('Deploy') {
      steps {
        withOpenBao(app: 'my-service', secrets: [
          [envVar: 'DB_PASSWORD', vaultKey: 'db_password'],
        ]) { sh './deploy.sh' }   // $DB_PASSWORD ใช้ได้ในนี้
      }
    }
  }
}
```

### ⏭️ ค้าง: push main แล้ว trigger build `sample-app` เพื่อพิสูจน์ (Jenkins ดึงจาก GitHub@main)

---

## 2026-08-12 — แยก env staging/prod ✅

### แนวคิด 3 ชั้น (อย่าปน)
1. **แยก path ที่ OpenBao** (data) — `secret/<app>/<env>` ← ทำแล้ว (ฐาน ต้องมีเสมอ)
2. **แยกสิทธิ์ token/policy** ต่อ env — ยังไม่ทำ (ตอนนี้ยังใช้ token `root` เดียว); เตรียม hook ไว้แล้ว
   ผ่าน `perEnvCred: true` → จะไปหา credential `openbao-token-<env>`
3. **build ไหนยิง env ไหน** (routing) — เลือก **branch-based**: `main`→prod, branch อื่น→staging

### สิ่งที่ทำ
- `vars/withOpenBao.groovy` รับ param `env` → derive `vaultPath = secret/<app>/<env>` อัตโนมัติ
  (ไม่ใส่ env ก็ยัง fallback เป็น `secret/<app>` เหมือนเดิม)
- `app/Jenkinsfile`: คำนวณ `TARGET_ENV` จาก `env.BRANCH_NAME` + เพิ่ม stage `Approve prod`
  (`input`) กัน deploy prod หลุด + ส่ง `env: TARGET_ENV` เข้า `withOpenBao`
- `compose/seed-openbao.sh`: seed 2 path — `secret/sample-app/staging` และ `secret/sample-app/prod`

### ⚠️ ต้อง re-seed หลัง pull (dev mode เก็บใน memory): `bash compose/seed-openbao.sh`
### ⏭️ ค้าง: push → build. หมายเหตุ job ปัจจุบัน poll `main` เดียว → จะได้ env=prod เสมอ
###        (จะเห็น input approval). อยากเทส staging ต้องมี branch อื่น หรือทำ multibranch job

---

## 2026-08-12 — Security gate (Trivy) ✅ ทำก่อน ArgoCD

### สิ่งที่ทำ
- **custom Jenkins image**: `compose/jenkins/Dockerfile` = `jenkins/jenkins:lts-jdk17` + Trivy CLI
  (pin `TRIVY_VERSION=0.58.1`) → `docker-compose.yml` เปลี่ยน jenkins เป็น `build: ./jenkins`
- **shared step** `vars/trivyScan.groovy` — `trivy fs` สแกน vuln+secret, gate `HIGH,CRITICAL`
  override ได้: `severity`, `exitCode` (0=report เฉยๆ), `path`, `secrets`
- `app/Jenkinsfile`: เพิ่ม stage `Trivy scan` (เรียก `trivyScan()`) คั่นก่อน Deploy
  → แยก step/stage ต่อ tool (Trivy แยกจาก SonarQube ทีหลัง) เวลา fail รู้ทันทีว่าตัวไหนล่ม

### ⚠️ ต้อง rebuild image ก่อนใช้ (image เดิมไม่มี trivy):
```bash
cd compose && docker compose up -d --build
```
### ⏭️ ค้าง: push → build. ถ้า trivy เจอ vuln HIGH/CRITICAL ใน dependency จะ fail (ปรับ severity ได้)
### 🔜 SonarQube (code quality/SAST) — เฟสถัดไป ต้องเพิ่ม service+DB ใน compose

---

## 2026-08-12 — เลิกใช้ init script, ลงทะเบียน Shared Library ที่ GUI แทน ✅

### เหตุผล: GUI ง่ายกว่า ไม่ซับซ้อน (init.groovy.d ต้องเขียน groovy + mount)
- **ลบ** `compose/jenkins-init/configure-shared-library.groovy` + เอา mount `init.groovy.d` ออกจาก compose
- ตอนนี้ลงทะเบียน library เองที่ **Manage Jenkins → System → Global Pipeline Libraries → Add**
  `Name=cicd-template`, `Default version=main`, Modern SCM → Git → repo URL
- ⚠️ library ที่ลงไว้แล้วอยู่ใน volume `jenkins_home` (ไม่หายตอน restart) — **หายเฉพาะถ้า `down -v`**
  ถ้า down -v แล้วต้องไปกรอกใหม่ที่ GUI (ไม่มี auto แล้ว)

---

## 2026-08-12 — SonarQube hard gate ✅ (code เสร็จ, เหลือกดตั้งค่า UI)

### สิ่งที่ทำ (auto แล้ว)
- compose: เพิ่ม service `sonarqube` (lts-community, H2 ในตัว, ปิด ES bootstrap check) UI = http://localhost:19000
- `jenkins/Dockerfile`: bake SonarScanner CLI 6.2.1.4610 + ลง plugin `sonar` (มี withSonarQubeEnv/waitForQualityGate)
- `vars/sonarScan.groovy`: analysis (async upload) → `waitForQualityGate abortPipeline:true` (ไม่ผ่าน=หยุด)
- `app/Jenkinsfile`: เพิ่ม stage `SonarQube` (แยกจาก `Trivy scan` → fail แล้วรู้ว่าตัวไหน)
- verify แล้ว: scanner+plugin อยู่ใน jenkins, SonarQube UP v9.9.8

### ⏭️ ต้องกดใน UI เอง (ครั้งเดียว) ให้ hard gate ทำงาน
1. **SonarQube** http://localhost:19000 login `admin`/`admin` → เปลี่ยนรหัส
2. **สร้าง token**: My Account → Security → Generate token → copy
3. **Jenkins credential**: เพิ่ม Secret text = token นั้น (เช่น id `sonarqube-token`)
4. **ผูก server**: Manage Jenkins → System → SonarQube servers → Add
   Name=`sonarqube`, URL=`http://sonarqube:9000`, Server auth token = credential ข้างบน
   (☑ Environment variables / enable injecting)
5. **webhook**: SonarQube → Administration → Configuration → Webhooks → Create
   URL=`http://jenkins:8080/sonarqube-webhook/`  ← ตัวปลุก waitForQualityGate
> ⚠️ Name ใน step 4 ต้องตรงกับ `server:'sonarqube'` ใน sonarScan(); URL ใช้ชื่อ service ใน compose network ไม่ใช่ localhost

---

## 2026-08-12 (ปิดวัน) — pipeline เขียวครบ loop 🎉✅

**Build → Test → Trivy → SonarQube → Deploy เดินครบ ผ่าน hard gate จริง**

### เพิ่มช่วงบ่าย
- `sample-app` เป็น **Vite + React จริง** (`npm ci && vite build`) → bake **Node 20** เข้า Jenkins image
- **vitest + coverage**: 2 เทส `App.jsx` (100%) → ต่อ `lcov` เข้า Sonar (`sonar.javascript.lcov.reportPaths`),
  กัน `main.jsx` ออกจาก coverage (`sonar.coverage.exclusions`)
- ปรับ **Quality Gate ที่ Sonar UI** (สร้าง gate "soft coverage" → Set as Default) แทนการฝืนโค้ดให้ถึง 80%
  → คง `gate: true` (hard) ไว้ แต่ **maintainer คุมเกณฑ์กลางที่ Sonar ที่เดียว** (ไม่ต้องแก้โค้ด)
- `sonarScan` echo **ลิงก์คลิกได้** `http://localhost:19000/dashboard?id=<key>` (scanner log โชว์ `sonarqube:9000` ที่ host เปิดไม่ได้)
- เอา `post{}` + `Approve prod` ออก, `TARGET_ENV='prod'` fixed hardcode

### ⚙️ Infra fix สำคัญวันนี้
- **Docker RAM 1.9GB → 8GB** ผ่าน `~/.wslconfig` (`[wsl2] memory=8GB`) — SonarQube (มี Elasticsearch) กินสเปกจน
  เครื่องค้าง Jenkins แทบเข้าไม่ได้/restart เอง → apply ด้วย `wsl --shutdown` + เปิด Docker Desktop ใหม่
- **port `50000→50001`** (WinNAT จอง 50000-50059 → `docker start jenkins` ค้างที่ `created`)
- **Trivy pin `0.73.0`** (0.58.1 โหลดไม่ได้ 404 จาก get.trivy.dev)
- ⚠️ อย่ายิง `docker start` ซ้อนกันหลายตัว → Docker Desktop start-path ค้าง ต้อง restart

### 🧩 Pipeline ปัจจุบัน (`app/Jenkinsfile`)
`Build (npm ci+build) → Test (vitest+coverage) → Trivy scan → SonarQube (hard gate) → Deploy (withOpenBao prod)`

### 🔀 Design ที่ยึด (สรุปทั้งวัน)
- template กลาง = **shared steps บางๆ ต่อ tool**: `withOpenBao`, `trivyScan`, `sonarScan` — consumer เขียน Jenkinsfile ปกติเอง
- **แยก stage/step ต่อ tool** → fail แล้วรู้ทันทีว่าตัวไหนล่ม
- ปลายทาง (vaultPath/env, quality gate, registry) **repo/maintainer คุมเอง** ผ่าน param/UI ไม่ lock-in
- ลงทะเบียน library + config ทุกอย่าง **ที่ GUI** (ดู `docs/gui-setup.md`)

### ⏭️ ค้าง/เลื่อนไว้ (คุยแล้ววันนี้)
- **auto-seed OpenBao** — dev mode หายทุก restart, ยัง `bash seed-openbao.sh` เอง (เลื่อน)
- **permission/user เข้า Jenkins+Sonar** — ตอนนี้ admin เดี่ยว → เฟส platform (แนะนำ SSO/OIDC)
- **แยก token/policy ต่อ env** (ชั้น 2) — ยังใช้ root เดียว, hook `perEnvCred` เตรียมไว้

---

## 2026-08-14 — `platform/argocd/` คุม ArgoCD ครบวงจร ✅ (เข้า UI ง่ายแล้ว)

### ปัญหาที่แก้
ArgoCD รันอยู่ใน cluster แต่ **ไม่มีที่มาใน repo เลย** (ติดตั้งด้วยมือ, ไม่มีสคริปต์) →
รื้อ cluster = หาย สร้างคืนไม่ได้. เข้า UI ก็ต้อง port-forward + งม base64 password ทุกครั้ง

### สิ่งที่ทำ — ไฟล์ใหม่ล้วน ไม่แตะของเดิม
| ไฟล์ | ทำอะไร |
|---|---|
| `platform/argocd/install.sh` | apply manifest `v3.5.1` (`--server-side`) → `server.insecure=true` → patch svc NodePort → รอ ready → apply `apps/` ทั้งโฟลเดอร์ |
| `platform/argocd/open.sh` | เปิด port-forward **background** + echo URL/user/password (`--stop` เพื่อปิด) |
| `platform/argocd/reset-password.sh` | รีเซ็ตรหัส admin เมื่อ login ไม่ผ่าน (ถามยืนยัน) |
| `platform/argocd/uninstall.sh` | ลบ ns argocd + CRD (ถามยืนยัน) |
| `platform/argocd/README.md` | URL/creds/คำสั่ง + คำเตือน local-only |
- แก้ `BOOTSTRAP.md` ข้อ 1+5 (เดิมเขียน helm ซึ่งไม่ตรงของจริง — เครื่องนี้ไม่มี helm)

### ตัดสินใจไว้ (เหตุผล)
- **manifest ไม่ใช่ helm** — ของจริงติดแบบนี้อยู่แล้ว, ไม่ต้องลง tool เพิ่ม/ไม่ต้องรื้อ.
  helm ค่อยย้ายตอนอยากคุม config หลายจุด (ingress/SSO/HA)
- **`server.insecure`** → UI เป็น http ไม่ต้องกดข้ามหน้าเตือน cert (เหมือน Jenkins/Sonar)
- **password คงสุ่มไว้** ไม่ hardcode ลง git — `open.sh` echo ให้แทน
- **install.sh apply `apps/` ให้เลย** — เพิ่ม app ใหม่ = วางไฟล์ใน `apps/` แล้วรันซ้ำ (idempotent)

### ⚠️ Gotcha ใหญ่ที่เจอ — NodePort ใช้ไม่ได้บน Docker Desktop
Docker Desktop k8s รุ่นใหม่รัน node ใน VM แยก (แบบ kind, `desktop-control-plane` ไม่โผล่ใน `docker ps`)
→ **NodePort ไม่ทะลุออก localhost** และ **ไม่มี LoadBalancer provider** (`EXTERNAL-IP` ค้าง `<pending>`)
→ ทางเข้าจริง = `port-forward` ที่ `open.sh` รันแบบ background ให้
> patch NodePort ยังคาไว้ในสคริปต์ — ถ้าย้ายไป **k3d** (`k3d cluster create -p "30080:30080@server:0"`)
> จะเข้าตรงๆ ได้ทันทีโดยไม่ต้อง port-forward

### ⚠️ Gotcha #2 — "Invalid username or password" ทั้งที่กรอกรหัสจาก open.sh ถูก (เจอ 2 ครั้งแล้ว)
ArgoCD เก็บ **hash** ที่ secret `argocd-secret` (`admin.password`) แต่รหัส **plain text** อยู่ที่
secret คนละตัว (`argocd-initial-admin-secret`). ถ้า 2 ตัวมาจากคนละรอบติดตั้ง → hash ไม่ตรงกับรหัสที่โชว์
ครั้งนี้ต่างกัน 6 ชม. (`admin.passwordMtime` = 08-13T00:00:00Z แต่ initial secret สร้าง 08-13T06:06:55Z)
```bash
bash platform/argocd/reset-password.sh   # ลบ initial secret + ล้าง hash + restart → สุ่มใหม่ให้ตรงกัน
```
> ต้อง **ลบ `argocd-initial-admin-secret` ด้วย** ไม่ใช่ล้างแค่ hash — ไม่งั้น argocd-server เห็นว่ามีอยู่แล้วและไม่เขียนรหัสใหม่ลงไป
> เช็คว่าเพี้ยนไหม: timestamp ของ `admin.passwordMtime` ต้องตรงกับ `creationTimestamp` ของ initial secret

### ✅ verify แล้ว
`http://localhost:30080` → HTTP 200 (title: Argo CD) · `sample-app` = **Synced / Healthy** · รัน `open.sh` ซ้ำไม่เปิดซ้อน
· `POST /api/v1/session` ด้วยรหัสจาก `open.sh` → **200** (หลัง reset-password)

---

## 🔜 ทำต่อ (ตามลำดับความสำคัญ)

1. เพิ่ม stage **build image จริง** (`docker build` + push registry) + **Trivy image scan** (ตอนนี้แค่ fs)
2. เพิ่ม **ArgoCD** (ต้องมี k8s → k3d) เข้าสู่ deploy จริง (`platform/` เตรียมไว้แล้ว — ต้องเติม `globalLibraries` ใน casc.yaml)
3. **auto-seed OpenBao** (QoL) — service `openbao-seed` ใน compose
4. **permission/SSO** เข้า Jenkins + Sonar (เฟส platform)
5. **แยก token/policy ต่อ env** ใน OpenBao (ชั้น 2 ของการแยก env)

## 📝 โน้ตดีไซน์เฟส 2 (คุยไว้ 2026-08-12 — ยังไม่ลงมือ)

### Config: secret vs non-secret (OpenBao ไม่ซ้ำกับ .env)
- **secret** (password/key/token) → **OpenBao** ต่อ env (มีแล้ว) — ห้ามอยู่ใน .env/git
- **non-secret** (API URL/flag/log level) → `.env`/ConfigMap ได้ (ไม่ลับ) หรือยัดเข้า OpenBao ต่อ env ด้วย → **เลิกใช้ .env เหลือ source เดียว**
- ⚠️ Vite `VITE_*` = **build-time** (bake ตอน build) → staging/prod ต่างค่า ต้อง build ต่อ env (`.env.<mode>`) หรือ runtime config; secret ห้ามอยู่ใน frontend

### Rollback = ฝั่ง CD ไม่ใช่ Jenkins
- GitOps: **rollback = `git revert` image tag ใน gitops → ArgoCD sync ตัวเก่า** (path เดียวกับ deploy)
- ArgoCD UI rollback = ฉุกเฉิน แต่ Git ยังชี้ใหม่ → `selfHeal` ตีกลับ ต้องแก้ Git ตาม
- เงื่อนไข: **tag image = commit SHA ไม่ใช่ `latest`**; OpenBao KV v2 เก็บ version secret → ย้อน secret แยกได้

### ArgoCD = platform ตัวเดียว (shared) เสิร์ฟทุก repo
- ArgoCD ติดตั้งครั้งเดียว (เหมือน Jenkins) — ไม่ใช่ต่อ repo
- cicd-template = (1) ที่อยู่ตัวตั้ง ArgoCD (`platform/argocd/`) + (2) ให้ **base chart/app-of-apps/Application template** ที่ consumer อ้าง
- consumer repo = มี **`Application` CR + manifest ของตัวเอง** (อ้าง chart กลาง) — sample-app ในรีโปนี้ = demo ฝั่ง CD
- symmetry: CI(Jenkins+shared library+Jenkinsfile) ↔ CD(ArgoCD+base chart+Application)

---

## ไฟล์อ้างอิง
- `docs/gui-setup.md` — ⭐ คู่มือตั้งค่า GUI ครบทุก service (Jenkins + OpenBao + SonarQube) URL/creds/ทุกขั้นที่กดเอง
- `platform/argocd/README.md` — ArgoCD: install/open/uninstall + URL/creds
- `docs/design-spec.md` — vision เต็ม 13 tools
- `docs/mvp-spec.md` — spec ของ MVP
- `BOOTSTRAP.md` — คำสั่ง deploy บน k8s (เฟส ArgoCD)
- `compose/README.md` — วิธีรัน local + ต่อ k3d
