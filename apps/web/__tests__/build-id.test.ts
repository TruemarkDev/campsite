import type { NextApiRequest, NextApiResponse } from 'next'
import { afterEach, describe, expect, it, vi } from 'vitest'

import handler from '../pages/api/build-id'

describe('build-id API route', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
  })

  it('returns the revision supplied to the staging web build', () => {
    vi.stubEnv('NEXT_PUBLIC_RELEASE_SHA', '7d7f8e4c9b')
    const json = vi.fn()
    const status = vi.fn().mockReturnValue({ json })

    handler({} as NextApiRequest, { status } as unknown as NextApiResponse)

    expect(status).toHaveBeenCalledWith(200)
    expect(json).toHaveBeenCalledWith({ buildId: '7d7f8e4c9b' })
  })
})
