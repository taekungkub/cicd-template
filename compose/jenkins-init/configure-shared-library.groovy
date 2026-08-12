// compose/jenkins-init/configure-shared-library.groovy
// ─────────────────────────────────────────────────────────────────────────────
// รันอัตโนมัติตอน Jenkins startup (mount ไปที่ /var/jenkins_home/init.groovy.d/)
// ลงทะเบียน Global Pipeline Library ชื่อ 'cicd-template' ชี้มาที่ repo กลางบน GitHub
// idempotent — รันซ้ำได้ ไม่สร้างซ้ำ
//
// ผลลัพธ์: repo ปลายทางเขียน Jenkinsfile ได้แค่
//   @Library('cicd-template@main') _
//   cicdPipeline(app: 'my-service', vaultPath: 'secret/my-service')
// ─────────────────────────────────────────────────────────────────────────────
import jenkins.model.Jenkins
import org.jenkinsci.plugins.workflow.libs.GlobalLibraries
import org.jenkinsci.plugins.workflow.libs.LibraryConfiguration
import org.jenkinsci.plugins.workflow.libs.SCMSourceRetriever
import jenkins.plugins.git.GitSCMSource

def LIB_NAME    = 'cicd-template'
def LIB_REPO    = 'https://github.com/taekungkub/cicd-template.git'
def DEFAULT_VER = 'main'

def jenkins = Jenkins.get()
def globalLibs = jenkins.getExtensionList(GlobalLibraries.class)[0]

// ถ้ามีชื่อนี้อยู่แล้ว ไม่ต้องทำซ้ำ
if (globalLibs.libraries.any { it.name == LIB_NAME }) {
  println "[init] Shared Library '${LIB_NAME}' มีอยู่แล้ว — ข้าม"
  return
}

def scmSource = new GitSCMSource(LIB_REPO)
def retriever = new SCMSourceRetriever(scmSource)

def libConfig = new LibraryConfiguration(LIB_NAME, retriever)
libConfig.defaultVersion  = DEFAULT_VER
libConfig.implicit        = false   // ต้อง @Library() ถึงจะโหลด
libConfig.allowVersionOverride = true

def newList = new ArrayList(globalLibs.libraries)
newList.add(libConfig)
globalLibs.libraries = newList

jenkins.save()
println "[init] ✅ ลงทะเบียน Shared Library '${LIB_NAME}' -> ${LIB_REPO}@${DEFAULT_VER}"
