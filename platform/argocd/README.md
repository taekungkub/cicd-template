# ArgoCD — ตัว deploy (CD)

โฟลเดอร์นี้คุม ArgoCD ทั้งหมด: ติดตั้ง, เข้าใช้งาน, ถอน, และรายชื่อ Application ที่ให้มันดูแล

## เข้าใช้งาน

```bash
bash platform/argocd/open.sh          # เปิดทางเข้า + บอก URL/user/password
bash platform/argocd/open.sh --stop   # ปิดทางเข้า
```

| | |
|---|---|
| URL | http://localhost:30080 |
| Username | `admin` |
| Password | รหัสสุ่มตอนติดตั้ง — `open.sh` ดึงมาให้ |

`open.sh` รัน `kubectl port-forward` แบบ **background** (ไม่ต้องเปิด terminal ค้าง) — รันครั้งเดียว
แล้วเปิด browser ได้เรื่อยๆ จนกว่าจะสั่ง `--stop` หรือ reboot. รันซ้ำได้ ไม่เปิดซ้อน

> **ทำไมไม่ใช้ NodePort ตรงๆ:** Docker Desktop k8s รุ่นใหม่รัน node ใน VM แยก (แบบ kind)
> → NodePort ไม่ทะลุออก `localhost` และไม่มี LoadBalancer provider (`EXTERNAL-IP` ค้าง `<pending>`)
> `install.sh` ยัง patch svc เป็น NodePort ไว้ให้ — ถ้าย้ายไป **k3d** ที่ map port ตอนสร้าง cluster
> (`k3d cluster create -p "30080:30080@server:0"`) จะเข้าได้ตรงๆ ไม่ต้อง port-forward

## ติดตั้ง / อัปเดต

```bash
bash platform/argocd/install.sh
```

รันซ้ำได้เสมอ — ของที่มีอยู่แล้วขึ้น `unchanged` ไม่สร้างซ้ำ ไม่ restart pod
สคริปต์ทำ 4 อย่าง:

1. apply manifest ArgoCD (pin `v3.5.1` — เปลี่ยนได้ด้วย `ARGOCD_VERSION=v3.6.0 bash install.sh`)
2. ตั้ง `server.insecure=true` → UI เป็น http ไม่ต้องกดข้ามหน้าเตือน cert
3. patch `svc/argocd-server` เป็น NodePort `30080` (เปลี่ยนได้ด้วย `ARGOCD_NODEPORT=...`)
4. apply ทุกไฟล์ใน `apps/`

## เพิ่ม app ใหม่

```bash
# 1. สร้างไฟล์ Application ใน apps/ (ก๊อป sample-app.yaml เป็นแบบ แล้วแก้ name/path/namespace)
# 2. ลงทะเบียน
bash platform/argocd/apply-apps.sh
```

ใช้ `apply-apps.sh` ไม่ใช่ `install.sh` — `install.sh` restart `argocd-server` ด้วย
ทำให้ port-forward ตาย ต้องรัน `open.sh` ใหม่โดยไม่จำเป็น

## วงจรใช้งานประจำวัน

| เหตุการณ์ | ทำอะไร |
|---|---|
| ปิดคอม / reboot | **ไม่ต้องทำอะไร** — k8s เก็บ state ไว้ ArgoCD ขึ้นเองพร้อม Docker Desktop |
| เปิดคอมมา | `bash platform/argocd/open.sh` (เปิด port-forward ที่ตายไปตอน reboot) |
| เพิ่ม/แก้ app | `bash platform/argocd/apply-apps.sh` |
| อัปเดต/ซ่อมตัว ArgoCD | `bash platform/argocd/install.sh` |
| ลบ ArgoCD ทิ้งจริงๆ | `bash platform/argocd/uninstall.sh` |

> เปิดคอมมาแล้ว `open.sh` error ว่าหา deploy ไม่เจอ = Docker Desktop ยัง start k8s ไม่เสร็จ
> (ใช้เวลา ~1–2 นาที) รอแล้วรันซ้ำ

## login ไม่ได้ — "Invalid username or password"

```bash
bash platform/argocd/reset-password.sh    # ถามยืนยันก่อน แล้วโชว์รหัสใหม่ให้
```

**สาเหตุ:** ArgoCD เก็บ **hash** ของรหัสไว้ที่ secret `argocd-secret` แต่รหัส **plain text**
ที่เอาไปกรอกอยู่ที่ secret คนละตัว (`argocd-initial-admin-secret`) — ถ้า 2 ตัวนี้มาจากคนละรอบ
ติดตั้ง (install ล้มกลางทาง / apply ทับ) hash จะไม่ตรงกับรหัสที่ `open.sh` โชว์ → login ไม่ผ่าน
ทั้งที่กรอกถูก

เช็คว่าเพี้ยนไหม (timestamp 2 ค่านี้ต้องตรงกัน):

```bash
kubectl -n argocd get secret argocd-secret -o jsonpath='{.data.admin\.passwordMtime}' | base64 -d
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.metadata.creationTimestamp}'
```

> รหัส admin เดิมถูกทิ้ง (รวมรหัสที่ตั้งเองใน UI) — Application/workload ที่ deploy ไว้ไม่กระทบ

## ถอน

```bash
bash platform/argocd/uninstall.sh    # ถามยืนยันก่อน
```

ลบ namespace `argocd` + CRD. app ที่ deploy ไว้ (เช่น ns `sample-app`) ไม่ถูกลบ

## apps/

| ไฟล์ | ดูแลอะไร |
|---|---|
| `sample-app.yaml` | sync `gitops/sample-app/` → namespace `sample-app` (`prune` + `selfHeal` เปิด) |

## ⚠️ config นี้ = local เท่านั้น

`install.sh` ตั้งค่าให้ "เข้าถึงง่ายบนเครื่องตัวเอง" โดยแลกกับความปลอดภัย:

- **`server.insecure`** — UI เป็น http ธรรมดา รหัสผ่าน admin วิ่งแบบ plain text
- **NodePort** — เปิด port บนเครื่องถาวร ไม่มีการจำกัดว่าใครเข้าได้

ยอมรับได้เฉพาะ cluster บนเครื่องตัวเอง (docker-desktop / k3d / kind) ที่ traffic ไม่ออกนอกเครื่อง

**ห้ามใช้ config นี้กับ cluster ที่คนอื่นเข้าถึงได้หรือเข้าถึงจากอินเทอร์เน็ต** — ArgoCD UI มีสิทธิ์ deploy
ได้ทั้ง cluster ใครเข้าถึงได้เท่ากับยึดระบบได้ ที่นั่นต้องเป็น https + cert จริง + SSO/RBAC เสมอ
