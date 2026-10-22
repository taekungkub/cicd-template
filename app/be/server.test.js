import { test, after } from 'node:test'
import assert from 'node:assert/strict'
import { app } from './server.js'

await new Promise((r) => app.listen(0, r))
const base = `http://localhost:${app.address().port}`
after(() => app.close())

test('GET /api/health → ok', async () => {
  const res = await fetch(`${base}/api/health`)
  assert.equal(res.status, 200)
  assert.deepEqual(await res.json(), { status: 'ok' })
})

test('GET /api/hello อ่าน GREETING จาก env', async () => {
  process.env.GREETING = 'hi test'
  assert.deepEqual(await (await fetch(`${base}/api/hello`)).json(), { message: 'hi test' })
})

test('path อื่น → 404', async () => {
  assert.equal((await fetch(`${base}/nope`)).status, 404)
})
