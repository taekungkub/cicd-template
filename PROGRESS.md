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

## 🔜 ทำต่อ (ตามลำดับความสำคัญ)

1. เพิ่ม stage **build image จริง** (`docker build` + push registry)
3. เพิ่ม **ArgoCD** (ต้องมี k8s → k3d) เข้าสู่ deploy จริง
4. เพิ่ม **security gate**: Trivy + SonarQube

## ไฟล์อ้างอิง
- `docs/design-spec.md` — vision เต็ม 13 tools
- `docs/mvp-spec.md` — spec ของ MVP
- `BOOTSTRAP.md` — คำสั่ง deploy บน k8s (เฟส ArgoCD)
- `compose/README.md` — วิธีรัน local + ต่อ k3d
