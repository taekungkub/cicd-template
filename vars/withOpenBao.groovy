// vars/withOpenBao.groovy
// ─────────────────────────────────────────────────────────────────────────────
// "template กลาง" — ส่วนเดียวที่แชร์ร่วมกันทุก repo คือ "การดึง env จาก OpenBao"
//
// แต่ละ repo เขียน Jenkinsfile ของตัวเองตามปกติ (build/test/deploy คนละภาษาได้)
// แล้วห่อเฉพาะ "ช่วงที่ต้องใช้ secret" ด้วย step นี้:
//
//   @Library('cicd-template@main') _
//
//   pipeline {
//     agent any
//     stages {
//       stage('Deploy') {
//         steps {
//           withOpenBao(app: 'my-service', env: 'prod', secrets: [
//             [envVar: 'DB_PASSWORD', vaultKey: 'db_password'],
//           ]) {
//             sh './deploy.sh'          // ในบล็อกนี้มี $DB_PASSWORD ใช้ได้เลย
//           }
//         }
//       }
//     }
//   }
//
// การแยก staging/prod (ดู PROGRESS.md):
//   - วิธี 1 (แยก path): ใส่ `env` → path กลายเป็น secret/<app>/<env> อัตโนมัติ
//   - วิธี 3 (build ไหนยิง env ไหน): ให้ consumer ตัดสิน env เอง (branch-based/param)
//                                    แล้วส่งค่าเข้ามาทาง `env:`
//
// ── repo custom ชี้เองได้ทุกอย่าง (default เป็นแค่ convention, override ได้หมด) ──
//
//   // 1) ยังไม่มี prod/staging → ไม่ต้องใส่ env → path = secret/<app>
//   withOpenBao(app: 'my-app', secrets: [[envVar: 'TOKEN', vaultKey: 'token']]) { ... }
//
//   // 2) path แปลกๆ ไม่ตาม convention → ใส่ vaultPath ตรงๆ (ชนะ app/env ทั้งหมด)
//   withOpenBao(app: 'legacy', vaultPath: 'secret/teamA/shared/config',
//     secrets: [[envVar: 'DB_URL', vaultKey: 'db_url']]) { ... }
//
//   // 3) ชื่อ env อื่น (dev/qa/uat) → ส่ง string อะไรก็ได้ → secret/<app>/<env>
//   withOpenBao(app: 'my-app', env: 'qa', secrets: [...]) { ... }
//
//   // 4) คนละ OpenBao/Vault ไปเลย (repo คนละทีม/คนละ cluster)
//   withOpenBao(app: 'x', vaultUrl: 'http://vault.teamB:8200',
//     vaultCred: 'teamB-token', vaultPath: 'kv/x', secrets: [...]) { ... }
//
// → template นี้บังคับแค่ "ดึงผ่าน withOpenBao" ทางเดียว; ปลายทางชี้ที่ไหน repo เจ้าของเลือกเอง
//
// ต้องมีใน Jenkins ก่อน:
//   1) plugin "HashiCorp Vault"
//   2) credential (default id = 'openbao-token', kind = Vault Token = "root")
//   3) Global Pipeline Library ชื่อ 'cicd-template' ชี้มาที่ repo นี้
// ─────────────────────────────────────────────────────────────────────────────

def call(Map config = [:], Closure body) {

  // ---- ค่า default + validation (ซ่อน config OpenBao ไว้ที่เดียว) -----------
  String app       = config.app       ?: error('withOpenBao: ต้องระบุ app')
  String env       = config.env ?: config.environment ?: ''   // 'staging' | 'prod' | '' (ไม่แยก)

  // วิธี 1 — แยก secret ตาม env: secret/<app>/<env>  (ถ้าไม่ใส่ env → secret/<app> เหมือนเดิม)
  String vaultPath = config.vaultPath ?: (env ? "secret/${app}/${env}" : "secret/${app}")
  String vaultUrl  = config.vaultUrl  ?: 'http://openbao:8200'   // service name ใน compose network

  // วิธี 2 (แยกสิทธิ์) — ถ้าจะแยก token/policy ต่อ env ในอนาคต ให้ตั้ง credential ชื่อ
  // 'openbao-token-<env>' ใน Jenkins แล้วส่ง perEnvCred: true (ตอนนี้ default ใช้ token เดียว)
  String vaultCred = config.vaultCred ?:
      ((config.perEnvCred && env) ? "openbao-token-${env}" : 'openbao-token')
  int    engineVer = (config.engineVersion ?: 2) as int

  // secret mapping: [[envVar: 'DB_PASSWORD', vaultKey: 'db_password'], ...]
  List secrets = config.secrets ?: [[envVar: 'DB_PASSWORD', vaultKey: 'db_password']]

  def vaultSecrets = [[
    path:          vaultPath,     // KV v2 path (plugin เติม /data ให้เอง)
    engineVersion: engineVer,
    secretValues:  secrets,
  ]]
  def configuration = [
    vaultUrl:          vaultUrl,
    vaultCredentialId: vaultCred,
    engineVersion:     engineVer,
  ]

  withVault([configuration: configuration, vaultSecrets: vaultSecrets]) {
    // ในบล็อกนี้ secret ถูก inject เป็น env var แล้ว (Jenkins mask ให้ ****)
    def names = secrets.collect { it.envVar }.join(', ')
    echo "🔐 [${env ?: 'default'}] injected: ${names} (จาก ${vaultPath})"
    body()
  }
}
