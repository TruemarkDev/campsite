// @vitest-environment node

import { describe, expect, it } from 'vitest'

describe('Lottie', () => {
  it('can load the component module without a DOM', async () => {
    const lottieModule = await import('./Lottie')

    expect(lottieModule.Lottie).toBeTypeOf('function')
  })
})
