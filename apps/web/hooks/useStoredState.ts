import { useCallback, useState } from 'react'

import { getFromStorage } from '@/utils/getFromStorage'
import { getWebStorage } from '@/utils/getWebStorage'
import { setToStorageWithDefault } from '@/utils/setToStorageWithDefault'

function getStorageKey(key: string | string[]) {
  return typeof key === 'string' ? key : key.join(':')
}

export const RESET: unique symbol = Symbol()

export function useStoredState<T>(
  key: string | string[],
  initialValue: T,
  storage: Storage | undefined = getWebStorage('localStorage')
): [T, (value: T | typeof RESET) => void] {
  const storageKey = getStorageKey(key)
  const [value, setValue] = useState(() => getFromStorage(storage, storageKey, initialValue))

  const wrappedSetValue = useCallback(
    (next: T | typeof RESET) => {
      const nextValue = next === RESET ? initialValue : next

      setToStorageWithDefault(storage, storageKey, nextValue, initialValue)
      setValue(nextValue)
    },
    [initialValue, storage, storageKey]
  )

  return [value, wrappedSetValue]
}
