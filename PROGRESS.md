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

## 🔜 ทำต่อ (ตามลำดับความสำคัญ)

1. เพิ่ม stage **build image จริง** (`docker build` + push registry)
3. เพิ่ม **ArgoCD** (ต้องมี k8s → k3d) เข้าสู่ deploy จริง
4. เพิ่ม **security gate**: Trivy + SonarQube

## ไฟล์อ้างอิง
- `docs/design-spec.md` — vision เต็ม 13 tools
- `docs/mvp-spec.md` — spec ของ MVP
- `BOOTSTRAP.md` — คำสั่ง deploy บน k8s (เฟส ArgoCD)
- `compose/README.md` — วิธีรัน local + ต่อ k3d
