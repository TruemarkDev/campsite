import { AuthenticationError } from '../types'

describe('AuthenticationError', () => {
  it.each(['no-token', 'invalid-type'] as const)('exposes the %s reason', (reason) => {
    const error = new AuthenticationError(reason)

    expect(error).toBeInstanceOf(Error)
    expect(error.message).toBe(reason)
    expect(error.reason).toBe(reason)
  })
})
