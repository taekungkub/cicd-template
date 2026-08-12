// vars/securityScan.groovy
// ─────────────────────────────────────────────────────────────────────────────
// "template กลาง" — shared security gate ด้วย Trivy (แนวเดียวกับ withOpenBao)
//
// สแกน filesystem ของ repo: หา vuln ใน dependency + secret ที่เผลอ commit
// language-agnostic → ใช้ได้ทุก repo ไม่ว่าเขียนภาษาอะไร
//
//   @Library('cicd-template@main') _
//
//   stage('Security scan') {
//     steps { securityScan() }                     // default: fail เมื่อเจอ HIGH,CRITICAL
//   }
//
// override ได้:
//   securityScan(severity: 'CRITICAL')             // เข้มเฉพาะ CRITICAL
//   securityScan(exitCode: 0)                       // report อย่างเดียว ไม่ fail build
//   securityScan(path: 'app', secrets: false)       // สแกนแค่โฟลเดอร์ app, ปิด secret scan
//
// ต้องมีใน Jenkins agent: trivy CLI (bake ไว้ใน compose/jenkins/Dockerfile แล้ว)
// ─────────────────────────────────────────────────────────────────────────────

def call(Map config = [:]) {
  String  scanPath = config.path     ?: '.'
  String  severity = config.severity ?: 'HIGH,CRITICAL'
  int     exitCode = (config.exitCode != null ? config.exitCode : 1) as int  // 1 = fail build เมื่อเจอ
  boolean secrets  = (config.secrets != false)                               // default สแกน secret ด้วย
  String  scanners = secrets ? 'vuln,secret' : 'vuln'

  echo "🛡️  trivy fs [${severity}] scanners=${scanners} ที่ ${scanPath}"
  sh """
    trivy fs \
      --scanners ${scanners} \
      --severity ${severity} \
      --exit-code ${exitCode} \
      --no-progress \
      ${scanPath}
  """
}
