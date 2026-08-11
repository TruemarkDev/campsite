// @vitest-environment node

import { describe, expect, it } from 'vitest'

describe('getLottieThumbnailAndDuration', () => {
  it('can load the upload utility without a DOM', async () => {
    const lottieModule = await import('./getLottieThumbnailAndDuration')

    expect(lottieModule.getLottieThumbnailAndDuration).toBeTypeOf('function')
  })
})
