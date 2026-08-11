const WEB_URL_PROD = 'https://camp.polo-apps.com'
const WEB_URL_DEV = 'http://app.campsite.test:3000'

const SITE_URL_PROD = 'https://www.campsite.com'
const SITE_URL_DEV = 'http://campsite.test:3003'

const SYNC_URL_PROD = 'wss://camp-sync.polo-apps.com'
const SYNC_URL_DEV = 'ws://localhost:9000'

export const IS_PRODUCTION = process.env.NODE_ENV === 'production'
export const SCOPE_COOKIE_NAME = 'scope'
export const POLL_OPTION_DESCRIPTION_LENGTH = 32

export const IS_NGROK = !!process.env.NEXT_PUBLIC_IS_NGROK

const environmentUrl = (name: string, productionDefault: string, developmentDefault: string) =>
  process.env[name] || (IS_PRODUCTION ? productionDefault : developmentDefault)

// NEXT_PUBLIC values are embedded by Next.js at build time. Keeping the
// current production URLs as defaults lets the polo-apps and tokdio builds run
// concurrently from the same revision.
export const WEB_URL = environmentUrl('NEXT_PUBLIC_WEB_URL', WEB_URL_PROD, WEB_URL_DEV)
export const SITE_URL = environmentUrl('NEXT_PUBLIC_SITE_URL', SITE_URL_PROD, SITE_URL_DEV)
export const SYNC_URL = environmentUrl('NEXT_PUBLIC_SYNC_URL', SYNC_URL_PROD, SYNC_URL_DEV)

export const DESKTOP_APP_PROTOCOL = IS_PRODUCTION ? 'campsite://' : 'campsite-dev://'
export const LAST_CLIENT_JS_BUILD_ID_LS_KEY = 'latest-js-time'

export const RAILS_API_URL = environmentUrl(
  'NEXT_PUBLIC_API_URL',
  'https://camp-api.polo-apps.com',
  'http://api.campsite.test:3001'
)

const RAILS_AUTH_URL_PROD_COM = 'https://camp-auth.polo-apps.com'

export const RAILS_AUTH_URL = environmentUrl(
  'NEXT_PUBLIC_AUTH_URL',
  RAILS_AUTH_URL_PROD_COM,
  'http://auth.campsite.test:3001'
)
export const RAILS_ADMIN_URL = environmentUrl(
  'NEXT_PUBLIC_ADMIN_URL',
  'https://camp-admin.polo-apps.com',
  'http://admin.campsite.test:3001'
)

/*
  Not using an env variable because we use this variable in the browser, which
  requires extra config with Next.js to send env variables to the browser.
*/
export const IMGIX_DOMAIN = environmentUrl(
  'NEXT_PUBLIC_IMGIX_URL',
  'https://truecamp.imgix.net',
  'https://campsite-dev.imgix.net'
)

export const FIGMA_PLUGIN_URL = process.env.NEXT_PUBLIC_FIGMA_PLUGIN_URL
export const ZAPIER_APP_URL = 'https://zapier.com/apps/campsite/integrations'
export const CAL_DOT_COM_APP_URL = 'https://app.cal.com/apps/campsite'

export const LINEAR_CALLBACK_URL = `${RAILS_API_URL}/v1/integrations/linear/callback`
export const LINEAR_CLIENT_ID = process.env.NEXT_PUBLIC_LINEAR_CLIENT_ID!
export const LINEAR_APP_URL = process.env.NEXT_PUBLIC_LINEAR_APP_URL

export const ONBOARDING_STEP_KEY = 'onboardingStep'
export const ONBOARDING_SHARED_POSTS_KEY = 'onboardingPostIds'

export const PUSHER_KEY = process.env.NEXT_PUBLIC_PUSHER_KEY!
export const PUSHER_APP_CLUSTER = process.env.NEXT_PUBLIC_PUSHER_CLUSTER!

// Key is generated from the VAPID keys in the Rails app but without padding ("=")
export const WEB_PUSH_PUBLIC_KEY = process.env.NEXT_PUBLIC_WEB_PUSH_PUBLIC_KEY!

const DEFAULT_SEO_TITLE = 'Campsite — Work communication for distributed teams'
const DEFAULT_SEO_DESCRIPTION =
  'Campsite is designed for distributed teams to cut through the noise of daily work — move faster with more transparent, organized, and thoughtful conversations.'
const DEFAULT_SEO_IMAGE = {
  url: `${SITE_URL}/og/default.png`,
  alt: 'Campsite'
}

export const DEFAULT_SEO = {
  metadataBase: new URL(SITE_URL),
  alternates: {
    canonical: './'
  },
  title: DEFAULT_SEO_TITLE,
  description: DEFAULT_SEO_DESCRIPTION,
  openGraph: {
    type: 'website',
    locale: 'en_US',
    url: SITE_URL,
    site_name: 'Campsite', // used by next-seo
    siteName: 'Campsite', // used by next.js
    images: [DEFAULT_SEO_IMAGE]
  },
  twitter: {
    title: DEFAULT_SEO_TITLE,
    description: DEFAULT_SEO_DESCRIPTION,
    images: [DEFAULT_SEO_IMAGE],
    handle: '@trycampsite',
    site: '@trycampsite',
    cardType: 'summary_large_image'
  }
}

export const MAX_FILE_NUMBER = 10
export const ONE_GB = 1024 * 1024 * 1024

export const COMMUNITY_SLUG = 'design'
export const CAMPSITE_SCOPE = 'campsite'

export const COUNTED_ROLES = ['admin', 'member']

export * from './slack'
