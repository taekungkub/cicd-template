// app/be/server.js — mock backend (Node stdlib ไม่มี dependency)
// ponytail: mock เท่านั้น — ถ้าต้องการ route/validation/DI จริง เปลี่ยนเป็น NestJS/Express
// config อ่านจาก env ตอน runtime → k8s ได้จาก OpenBao ผ่าน ESO + envFrom
import { createServer } from 'node:http'

export const app = createServer((req, res) => {
  const send = (code, body) => {
    res.writeHead(code, { 'content-type': 'application/json' })
    res.end(JSON.stringify(body))
  }
  if (req.url === '/api/health') return send(200, { status: 'ok' })
  if (req.url === '/api/hello') return send(200, { message: process.env.GREETING || 'hello from be' })
  send(404, { error: 'not found' })
})

// listen เฉพาะตอนรันตรง (`node server.js`) — test import แล้ว listen port สุ่มเอง
if (process.argv[1]?.endsWith('server.js')) {
  const port = process.env.PORT || 3000
  app.listen(port, () => console.log(`be listening on :${port}`))
}
