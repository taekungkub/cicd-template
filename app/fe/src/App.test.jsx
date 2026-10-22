import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import App from './App.jsx'

describe('App', () => {
  beforeEach(() => {
    vi.stubGlobal(
      'fetch',
      vi.fn(() => Promise.resolve({ json: () => ({ message: 'hi mock' }) })),
    )
  })

  it('แสดงข้อความจาก be', async () => {
    render(<App />)
    expect(await screen.findByText(/be says: hi mock/)).toBeInTheDocument()
  })

  it('แสดงหัวข้อ sample-app', () => {
    render(<App />)
    expect(screen.getByText(/CICD Template — sample-app/i)).toBeInTheDocument()
  })

  it('ปุ่ม count เพิ่มขึ้นเมื่อคลิก', () => {
    render(<App />)
    fireEvent.click(screen.getByRole('button', { name: /count = 0/i }))
    expect(screen.getByRole('button', { name: /count = 1/i })).toBeInTheDocument()
  })
})
