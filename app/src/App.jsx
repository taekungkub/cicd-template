import { useState } from 'react'

export default function App() {
  const [count, setCount] = useState(0)

  return (
    <main style={{ fontFamily: 'sans-serif', textAlign: 'center', marginTop: '15vh' }}>
      <h1>🚀 CICD Template — sample-app</h1>
      <p>Vite + React ผ่าน pipeline: Build → Trivy → SonarQube → Deploy</p>
      <button onClick={() => setCount((c) => c + 1)}>count = {count}</button>
    </main>
  )
}
