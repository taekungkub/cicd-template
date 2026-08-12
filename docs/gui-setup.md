# GUI Setup — คู่มือตั้งค่า manual (local compose stack)

คู่มือรวมทุกอย่างที่ **ต้องกดใน UI เอง** สำหรับ stack local (`compose/`)
สิ่งที่ **auto แล้ว** (ไม่ต้องทำ): custom Jenkins image (Trivy + SonarScanner CLI + sonar plugin), compose services, `seed-openbao.sh`

> ⚠️ ทั้งหมดนี้เก็บใน docker volume — **หายเฉพาะเมื่อ `docker compose down -v`** (ถ้าหายต้องตั้งใหม่ตามคู่มือนี้)

---

## 0. เข้าถึงแต่ละ service

| Service | URL | login |
|---|---|---|
| **Jenkins** | http://localhost:9090 | `admin` / (รหัสที่ตั้งตอน setup) |
| **OpenBao** UI | http://localhost:18200 | Method: **Token**, Token: `root` |
| **SonarQube** | http://localhost:19000 | `admin` / `admin` (บังคับเปลี่ยนตอน login แรก) |

> port ถูก remap เพราะ Windows/WinNAT จอง: Jenkins 8080→**9090**, OpenBao 8200→**18200**, Sonar 9000→**19000**, agent 50000→**50001**

---

## 1. Jenkins — Plugins ที่ต้องมี

| Plugin | ใช้ทำอะไร | สถานะ |
|---|---|---|
| **HashiCorp Vault** | `withOpenBao` ดึง secret (`withVault`) | ต้องลงเอง (Manage Plugins) |
| **SonarQube Scanner** | `withSonarQubeEnv` / `waitForQualityGate` | ✅ bake ใน image แล้ว |
| Git / Pipeline | อ่าน Jenkinsfile จาก SCM | มากับ Jenkins |

---

## 2. Jenkins — Global Pipeline Library (ชี้ template กลาง)

**Manage Jenkins → System → Global Pipeline Libraries → Add**

| ช่อง | ค่า |
|---|---|
| Name | `cicd-template` |
| Default version | `main` |
| Allow default version to be overridden | ☑ |
| Retrieval method | Modern SCM |
| Source Code Management | Git |
| Project Repository | `https://github.com/taekungkub/cicd-template.git` |

> consumer อ้างด้วย **ชื่อ** `@Library('cicd-template@main') _` ไม่ใช่ URL — URL อยู่ที่นี่ที่เดียว

---

## 3. Jenkins — Credentials

**Manage Jenkins → Credentials → (global) → Add Credentials**

| id | Kind | ค่า | ใช้กับ |
|---|---|---|---|
| `openbao-token` | **Vault Token Credential** | `root` | `withOpenBao` (ดึง secret จาก OpenBao) |
| `sonarqube-token` | **Secret text** | \<token จาก SonarQube ข้อ 7.2\> | ผูก SonarQube server (ข้อ 5) |

---

## 4. Jenkins — Job `sample-app`

**New Item → Pipeline**

| ช่อง | ค่า |
|---|---|
| Definition | Pipeline script from SCM |
| SCM | Git |
| Repository URL | `https://github.com/taekungkub/cicd-template.git` |
| Branch | `main` |
| Script Path | `app/Jenkinsfile` |
| Build Triggers | ☑ Poll SCM — schedule `* * * * *` |

---

## 5. Jenkins — SonarQube server

**Manage Jenkins → System → SonarQube servers → Add SonarQube**

| ช่อง | ค่า |
|---|---|
| Name | `sonarqube` ← **ต้องตรงกับ** `server:'sonarqube'` ใน `sonarScan()` |
| Server URL | `http://sonarqube:9000` ← ชื่อ service ใน network **ไม่ใช่ localhost** |
| Server authentication token | credential `sonarqube-token` (ข้อ 3) |
| Environment variables (inject) | ☑ enable |

---

## 6. OpenBao

ส่วนใหญ่ทำผ่าน script ไม่ใช่ GUI — GUI ไว้ดู/แก้ secret

| เรื่อง | รายละเอียด |
|---|---|
| Jenkins ต่อ OpenBao ผ่าน | URL `http://openbao:8200` (ในโค้ด) + credential `openbao-token` (ข้อ 3) |
| Secret paths | `secret/sample-app/staging` · `secret/sample-app/prod` |
| keys ในแต่ละ path | `db_password`, `api_key`, `redis_url` |
| Seed secret | `bash compose/seed-openbao.sh` |

> ⚠️ OpenBao รัน **dev mode = เก็บใน memory** → ปิด container secret หาย ต้อง **re-seed** ทุกครั้งหลัง restart

---

## 7. SonarQube — Token + Webhook (ให้ hard gate ทำงาน)

| # | ที่ | ทำอะไร | ค่า |
|---|---|---|---|
| 7.1 | http://localhost:19000 | login + เปลี่ยนรหัส | `admin` / `admin` |
| 7.2 | My Account → Security | Generate token → copy | เอาไปใส่ credential ข้อ 3 |
| 7.3 | Administration → Configuration → **Webhooks** → Create | ให้ Sonar เรียกกลับ Jenkins | URL = `http://jenkins:8080/sonarqube-webhook/` |

> webhook (7.3) คือตัวปลุก `waitForQualityGate` — ถ้าไม่ตั้ง build จะ **ค้างที่ gate จน timeout**

---

## Gotchas สรุป

- **Name / URL ใน compose network** ใช้ชื่อ service (`sonarqube`, `jenkins`, `openbao`) ไม่ใช่ `localhost`
- `sonarqube` Name (ข้อ 5) ต้องตรงเป๊ะกับใน `sonarScan()` ไม่งั้น error `installation ... does not match`
- SonarQube webhook ไม่ตั้ง → build ค้างที่ Quality Gate
- `docker compose down -v` = ล้าง volume หมด → library + credential + job + secret หายทั้งหมด ต้องทำคู่มือนี้ใหม่
- SonarQube กินสเปกหนัก (มี Elasticsearch ในตัว) — ถ้าเครื่องช้า/ค้าง พิจารณาจำกัด RAM หรือรัน Sonar เฉพาะบาง build
