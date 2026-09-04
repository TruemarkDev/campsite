type WebStorage = 'localStorage' | 'sessionStorage'

export function getWebStorage(storage: WebStorage): Storage | undefined {
  if (typeof window === 'undefined') return undefined

  try {
    return window[storage]
  } catch {
    return undefined
  }
}
