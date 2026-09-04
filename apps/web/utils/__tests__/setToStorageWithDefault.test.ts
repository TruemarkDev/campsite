import { beforeEach, describe, expect, it, vi } from 'vitest'

import { setToStorageWithDefault } from '../setToStorageWithDefault'

describe('setToStorageWithDefault', () => {
  let storage: Storage

  beforeEach(() => {
    const values = new Map<string, string>()

    storage = {
      clear: () => values.clear(),
      getItem: (key) => values.get(key) ?? null,
      key: (index) => Array.from(values.keys())[index] ?? null,
      get length() {
        return values.size
      },
      removeItem: (key) => values.delete(key),
      setItem: (key, value) => values.set(key, value)
    }
  })

  it('it stores JSON', async () => {
    setToStorageWithDefault(storage, 'test', { a: 4 }, { a: 1 })
    expect(storage.getItem('test')).toEqual(JSON.stringify({ a: 4 }))
  })

  it('it removes null', async () => {
    setToStorageWithDefault(storage, 'test', null, { a: 1 })
    expect(storage.getItem('test')).toBeNull()
  })

  it('it removes initial', async () => {
    setToStorageWithDefault(storage, 'test', { a: 1 }, { a: 1 })
    expect(storage.getItem('test')).toBeNull()
  })

  it('does not throw when storage rejects writes', () => {
    vi.spyOn(storage, 'setItem').mockImplementation(() => {
      throw new DOMException('Storage quota exceeded', 'QuotaExceededError')
    })

    expect(() => setToStorageWithDefault(storage, 'test', { a: 4 }, { a: 1 })).not.toThrow()
  })

  it('does not throw when storage rejects removals', () => {
    vi.spyOn(storage, 'removeItem').mockImplementation(() => {
      throw new DOMException('Storage access denied', 'SecurityError')
    })

    expect(() => setToStorageWithDefault(storage, 'test', null, { a: 1 })).not.toThrow()
  })
})
