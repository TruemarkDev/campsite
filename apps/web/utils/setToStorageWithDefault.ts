import * as Sentry from '@sentry/nextjs'
import deepEqual from 'fast-deep-equal'

export function setToStorageWithDefault<T>(storage: Storage | undefined, key: string, value: T, initialValue: T) {
  if (!storage) return

  let valueLength = -1

  try {
    if (value == null || deepEqual(value, initialValue)) {
      storage.removeItem(key)
    } else {
      const stringify = JSON.stringify(value)

      valueLength = stringify.length
      storage.setItem(key, stringify)
    }
  } catch (error) {
    Sentry.setContext('storage', {
      key,
      valueLength: valueLength
    })
    Sentry.captureException(error)
  }
}
