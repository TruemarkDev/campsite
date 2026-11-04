import { RAILS_API_URL } from '@campsite/config'

import { browserApiUrl } from '../config/browser-api'

export const BROWSER_API_URL = browserApiUrl(
  RAILS_API_URL,
  process.env.NEXT_PUBLIC_SAME_ORIGIN_API,
  typeof window !== 'undefined'
)
