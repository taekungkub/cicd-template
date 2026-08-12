import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/  (ช่อง test อ่านโดย vitest)
export default defineConfig({
  plugins: [react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './src/setupTests.js',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov'],   // lcov → ให้ SonarQube อ่าน coverage
      include: ['src/**'],
      exclude: ['src/main.jsx', 'src/setupTests.js', '**/*.test.jsx'],  // bootstrap/test ไม่ต้องนับ
    },
  },
})
