// vars/sonarScan.groovy
// ─────────────────────────────────────────────────────────────────────────────
// "template กลาง" — code quality / SAST gate ด้วย SonarQube (แยกจาก trivyScan)
// stage แยกต่อ tool → fail แล้วรู้ทันทีว่าล่มเพราะ SonarQube ไม่ใช่ Trivy
//
//   @Library('cicd-template@main') _
//
//   stage('SonarQube') {
//     steps { sonarScan(projectKey: 'my-service', sources: 'app') }
//   }
//
// override ได้:
//   sonarScan(projectKey: 'x', gate: false)          // สแกนอย่างเดียว ไม่ block build
//   sonarScan(projectKey: 'x', gateTimeoutMinutes: 10)
//   sonarScan(projectKey: 'x', extraArgs: '-Dsonar.exclusions=**/*.test.js')
//
// ⚠️ SonarQube เป็น analysis แบบ ASYNC: scanner แค่ "อัปโหลด" แล้วจบ →
//    server คำนวณ quality gate ทีหลัง → ต้อง waitForQualityGate รอผลผ่าน webhook
//
// ต้องตั้งค่าใน Jenkins ก่อน (ครั้งเดียว):
//   1) plugin 'sonar' (bake ไว้ใน compose/jenkins/Dockerfile แล้ว) + sonar-scanner CLI (bake แล้ว)
//   2) Manage Jenkins → System → SonarQube servers: name='sonarqube', URL=http://sonarqube:9000, + token cred
//   3) SonarQube UI → generate token → เก็บเป็น Jenkins credential (Secret text)
//   4) SonarQube UI → Administration → Webhooks → http://jenkins:8080/sonarqube-webhook/
//      (webhook นี่แหละที่ปลุก waitForQualityGate ให้รู้ว่า gate เสร็จ)
// ─────────────────────────────────────────────────────────────────────────────

def call(Map config = [:]) {
  String  projectKey     = config.projectKey ?: error('sonarScan: ต้องระบุ projectKey')
  String  serverName     = config.server     ?: 'localhost'   // ชื่อ SonarQube server ที่ตั้งใน Jenkins
  String  sources        = config.sources    ?: '.'
  boolean gate           = (config.gate != false)             // default = hard gate (ไม่ผ่าน = หยุด)
  int     gateTimeoutMin = (config.gateTimeoutMinutes ?: 5) as int
  String  extraArgs      = config.extraArgs  ?: ''

  // 1) analysis — อัปโหลดผลขึ้น SonarQube (withSonarQubeEnv ฉีด SONAR_HOST_URL + token ให้)
  echo "🔎 SonarQube analysis: ${projectKey} (sources=${sources})"
  withSonarQubeEnv(serverName) {
    sh """
      sonar-scanner \
        -Dsonar.projectKey=${projectKey} \
        -Dsonar.sources=${sources} \
        ${extraArgs}
    """
  }

  // 2) quality gate — รอ server คำนวณเสร็จ (ผ่าน webhook); ไม่ผ่าน = abort build
  if (gate) {
    echo "⏳ รอ Quality Gate (timeout ${gateTimeoutMin} นาที)..."
    timeout(time: gateTimeoutMin, unit: 'MINUTES') {
      waitForQualityGate abortPipeline: true
    }
  }
}
