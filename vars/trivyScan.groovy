// vars/trivyScan.groovy
// ─────────────────────────────────────────────────────────────────────────────
// "template กลาง" — security gate ด้วย Trivy (SCA + secret detection)
// แยกเป็น step เฉพาะ tool → เวลา fail รู้ทันทีว่าล่มเพราะ Trivy (ไม่ปนกับ sonarScan)
//
// สแกน filesystem ของ repo: หา vuln ใน dependency + secret ที่เผลอ commit
// language-agnostic → ใช้ได้ทุก repo ไม่ว่าเขียนภาษาอะไร
//
//   @Library('cicd-template@main') _
//
//   stage('Trivy scan') {
//     steps { trivyScan() }                        // default: fail เมื่อเจอ HIGH,CRITICAL
//   }
//
// override ได้:
//   trivyScan(severity: 'CRITICAL')                // เข้มเฉพาะ CRITICAL
//   trivyScan(exitCode: 0)                          // report อย่างเดียว ไม่ fail build
//   trivyScan(path: 'app', secrets: false)          // สแกนแค่โฟลเดอร์ app, ปิด secret scan
//
// ต้องมีใน Jenkins agent: trivy CLI (bake ไว้ใน compose/jenkins/Dockerfile แล้ว)
// ── ทีหลังจะมี sonarScan() แยกต่างหากสำหรับ code quality/SAST (คนละ tool คนละ stage) ──
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
