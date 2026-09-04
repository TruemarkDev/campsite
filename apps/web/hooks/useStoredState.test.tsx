import { renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { useStoredState } from './useStoredState'

describe('useStoredState', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('uses the initial value when local storage is unavailable', () => {
    vi.spyOn(window, 'localStorage', 'get').mockImplementation(() => {
      throw new DOMException('Storage access denied', 'SecurityError')
    })

    const { result } = renderHook(() => useStoredState('test', 'initial'))

    expect(result.current[0]).toBe('initial')
  })
})
