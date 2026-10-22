import { useEffect, useState } from 'react'

export default function App() {
  const [count, setCount] = useState(0)
  const [msg, setMsg] = useState('...')

  // เรียก be ผ่าน path สัมพัทธ์ /api → nginx (compose/k8s) หรือ vite proxy (npm run dev) ส่งต่อให้
  useEffect(() => {
    fetch('/api/hello')
      .then((r) => r.json())
      .then((d) => setMsg(d.message))
      .catch(() => setMsg('be ไม่ตอบ'))
  }, [])

  return (
    <main style={{ fontFamily: 'sans-serif', textAlign: 'center', marginTop: '15vh' }}>
      <h1>🚀 CICD Template — sample-app</h1>
      <p>Vite + React ผ่าน pipeline: Build → Trivy → SonarQube → Deploy</p>
      <p>be says: {msg}</p>
      <button onClick={() => setCount((c) => c + 1)}>count = {count}</button>
    </main>
  )
}
