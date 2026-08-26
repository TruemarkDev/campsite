import { act, render, screen, waitFor } from '@testing-library/react'
import toast from 'react-hot-toast'
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest'

import { ToasterProvider } from '../../../../packages/ui/src/Toast/ToasterProvider'

function animationKeyframes(element: HTMLElement) {
  const animationName = element.style.animation.split(' ')[0]
  const rule = Array.from(document.styleSheets)
    .flatMap((sheet) => Array.from(sheet.cssRules))
    .find((candidate) => candidate.cssText.includes(`@keyframes ${animationName}`))

  return rule?.cssText.replaceAll(/\s|0\./g, (match) => (match === '0.' ? '.' : ''))
}

describe('ToasterProvider', () => {
  beforeAll(() => {
    vi.stubGlobal(
      'matchMedia',
      vi.fn().mockReturnValue({
        matches: false,
        addListener: vi.fn(),
        removeListener: vi.fn()
      })
    )

    vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({
      bottom: 42,
      height: 42,
      left: 0,
      right: 237,
      top: 0,
      width: 237,
      x: 0,
      y: 0,
      toJSON: () => ({})
    })
  })

  afterEach(() => {
    act(() => {
      toast.remove()
    })
  })

  afterAll(() => {
    vi.restoreAllMocks()
    vi.unstubAllGlobals()
  })

  it('preserves the feedback toast surface and enter/exit motion', async () => {
    render(<ToasterProvider />)

    let id = ''

    act(() => {
      id = toast.success('Feedback shared. Thank you!')
    })

    const message = await screen.findByRole('status')
    const toastBar = message.parentElement

    expect(toastBar?.style.background).toBe('rgb(0, 0, 0)')
    expect(toastBar?.style.borderRadius).toBe('9999px')
    expect(toastBar?.style.boxShadow).toBe('none')
    expect(toastBar?.style.color).toBe('rgb(255, 255, 255)')
    expect(toastBar?.style.fontSize).toBe('14px')
    expect(toastBar?.style.fontWeight).toBe('500')

    await waitFor(() => {
      expect(toastBar?.style.animation).toContain('0.35s cubic-bezier(.21,1.02,.73,1) forwards')
    })
    expect(animationKeyframes(toastBar!)).toContain('0%{transform:translate3d(0,200%,0)scale(.6);opacity:.5;}')
    expect(animationKeyframes(toastBar!)).toContain('100%{transform:translate3d(0,0,0)scale(1);opacity:1;}')

    act(() => {
      toast.dismiss(id)
    })

    await waitFor(() => {
      expect(toastBar?.style.animation).toContain('0.4s forwards cubic-bezier(.06,.71,.55,1)')
    })
    expect(animationKeyframes(toastBar!)).toContain('100%{transform:translate3d(0,150%,-1px)scale(.6);opacity:0;}')
  })
})
