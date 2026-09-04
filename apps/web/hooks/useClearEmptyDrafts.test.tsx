import { renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { useClearEmptyDrafts } from './useClearEmptyDrafts'

describe('useClearEmptyDrafts', () => {
  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('does not fail when browser storage is unavailable', () => {
    vi.spyOn(window, 'localStorage', 'get').mockImplementation(() => {
      throw new DOMException('Storage access denied', 'SecurityError')
    })
    vi.spyOn(window, 'sessionStorage', 'get').mockImplementation(() => {
      throw new DOMException('Storage access denied', 'SecurityError')
    })

    expect(() => renderHook(() => useClearEmptyDrafts())).not.toThrow()
  })
})
