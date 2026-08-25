export interface Context {
  token: string
  schemaVersion: number
  organization: string
  type: string | null
  actorType: 'human' | 'agent'
  grantId?: string
  actorId?: string
  actorName?: string
  invokedBy?: string
}

export type AuthenticationErrorType = 'no-token' | 'invalid-type' | 'invalid-grant'

export class AuthenticationError extends Error {
  reason: AuthenticationErrorType

  constructor(reason: AuthenticationErrorType) {
    super(reason)
    this.reason = reason
  }
}
