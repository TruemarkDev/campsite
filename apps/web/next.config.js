/**
 * @type {import('next').NextConfig}
 */

const { withSentryConfig } = require('@sentry/nextjs')
const withBundleAnalyzer = require('@next/bundle-analyzer')({
  enabled: process.env.ANALYZE === 'true'
})

const { deploymentImageDomains, deploymentOrigins, deploymentUrls } = require('./config/deployment')
const { browserApiRewrites } = require('./config/browser-api')
const { contentSecurityHeaders } = require('./config/content-security-policy')

const cspResourcesByDirective = {
  'script-src': [
    "'self'",
    // Retained during the report-only rollout: statically rendered documents
    // contain inline Next.js hydration scripts. See docs/deployment/content-security-policy.md.
    "'unsafe-inline'",
    'todesktop-internal:',
    'blob:',
    // Development needs eval for HMR. Production necessity (including 100ms)
    // is measured by the stricter report-only policy before enforcement changes.
    "'unsafe-eval'"
  ],
  'style-src': [
    "'self'",
    // Inline styles (style-src 'unsafe-inline') are required in all environments for react-hot-toast and tip-tap.
    // https://github.com/timolins/react-hot-toast/issues/138
    // They're also required in development for hot module reloading.
    "'unsafe-inline'"
  ],
  'object-src': ["'none'"],
  'base-uri': ["'self'"],
  'connect-src': [
    "'self'",
    'blob:',
    'https://*.campsite.design',
    'wss://*.campsite.design',
    'https://*.campsite.co',
    'wss://*.campsite.co',
    'https://*.campsite.com',
    'wss://*.campsite.com',
    ...deploymentOrigins,
    process.env.NODE_ENV !== 'production' && 'http://api.campsite.test:3001',
    process.env.NODE_ENV !== 'production' && 'ws://localhost:9000',
    'https://campsite-media.s3.amazonaws.com',
    process.env.NODE_ENV !== 'production' && 'https://campsite-media-dev.s3.amazonaws.com',
    process.env.NODE_ENV !== 'production' && 'd1tk25h31rf8pv.cloudfront.net', // campsite-hls-dev
    'd2m0evjsyl9ile.cloudfront.net', // campsite-hls
    'https://o1244295.ingest.sentry.io',
    'https://*.lottiefiles.com',
    'https://*.100ms.live',
    'wss://*.100ms.live',
    'https://*.pusher.com',
    'wss://*.pusher.com',
    'https://campsite.imgix.net',
    deploymentUrls.imgix,
    deploymentUrls.cdn,
    process.env.NODE_ENV !== 'production' && 'https://campsite-dev.imgix.net',
    'https://react-tweet.vercel.app', // for react-tweet embeds
    'https://media.tenor.com' // used for Tenor gifs
  ],
  'font-src': ["'self'"],
  'img-src': [
    "'self'",
    'blob:',
    'data:',
    'https://campsite.imgix.net',
    deploymentUrls.imgix,
    deploymentUrls.cdn,
    'https://campsite.imgix.video',
    'https://campsite-api.imgix.net',
    'https://lh3.googleusercontent.com',
    'https://public.linear.app', // used for linear issue avatars
    'https://avatars.githubusercontent.com', // used for GitHub issue avatars
    'https://pbs.twimg.com', // used for Twitter avatars
    'https://abs.twimg.com', // used for Tweet previews
    process.env.NODE_ENV !== 'production' && 'https://campsite-dev.imgix.net',
    process.env.NODE_ENV !== 'production' && 'https://campsite-dev.imgix.video',
    process.env.NODE_ENV !== 'production' && 'https://campsite-api-dev.imgix.net',
    process.env.NODE_ENV !== 'production' && 'http://api.campsite.test:3001',
    'https://media.tenor.com' // used for Tenor gifs,
  ],
  'manifest-src': ["'self'"],
  'media-src': [
    "'self'",
    'blob:',
    'data:',
    'd2m0evjsyl9ile.cloudfront.net', // campsite-hls
    process.env.NODE_ENV !== 'production' && 'd1tk25h31rf8pv.cloudfront.net', // campsite-hls-dev
    'https://campsite.imgix.net',
    deploymentUrls.imgix,
    deploymentUrls.cdn,
    'https://campsite-api.imgix.net',
    'https://video.twimg.com', // used for Twitter videos
    process.env.NODE_ENV !== 'production' && 'https://campsite-dev.imgix.net',
    process.env.NODE_ENV !== 'production' && 'https://campsite-api-dev.imgix.net',
    'https://media.tenor.com' // used for Tenor gifs
  ],
  'worker-src': ["'self'", 'blob:']
}

/** @type {import('next').NextConfig} */
const moduleExports = {
  ...(process.env.CAMPSITE_BROWSER_TEST === '1' && {
    distDir: process.env.BROWSER_NEXT_DIST_DIR
  }),
  allowedDevOrigins: ['app.campsite.test', new URL(deploymentUrls.web).hostname],
  output: 'standalone',
  experimental: {
    externalDir: true,
    clientRouterFilter: false
  },
  transpilePackages: [
    '@campsite/ui',
    '@campsite/types',
    '@campsite/config',
    '@campsite/regex',
    '@campsite/editor',
    'react-tweet'
  ],
  reactStrictMode: true,
  images: {
    unoptimized: true,
    remotePatterns: [
      ...deploymentImageDomains,
      'app.campsite.design',
      'app.campsite.co',
      'app.campsite.com',
      'app.campsite.test',
      'avatars.slack-edge.com',
      'campsite.imgix.net',
      'campsite-dev.imgix.net',
      'lh3.googleusercontent.com',
      'uploads.linear.app'
    ].map((hostname) => ({ hostname }))
  },
  async redirects() {
    return [
      {
        source: '/:org/invitation',
        destination: '/:org',
        permanent: false
      },
      {
        source: '/:org/inbox2',
        destination: `/:org/inbox/updates`,
        permanent: true
      },
      {
        source: '/:org/inbox',
        destination: `/:org/inbox/updates`,
        permanent: true
      },
      {
        source: '/:org/settings/people/:role*',
        destination: `/:org/people`,
        permanent: true
      },
      {
        source: '/:org/settings/tags',
        destination: `/:org/settings`,
        permanent: true
      },
      {
        source: '/:org/settings/projects',
        destination: `/:org/projects`,
        permanent: true
      },
      {
        source: '/:org/onboard/spaces',
        destination: `/:org/onboard/channels`,
        permanent: true
      }
    ]
  },
  async headers() {
    return [
      {
        // Apply these headers to all routes in your application.
        source: '/:path*',
        headers: [
          ...contentSecurityHeaders(cspResourcesByDirective, process.env.NODE_ENV, deploymentUrls.web),
          {
            key: 'X-Frame-Options',
            value: 'SAMEORIGIN'
          }
        ]
      },
      {
        // Sentry Profiling
        // @see https://docs.sentry.io/platforms/javascript/profiling/#step-2-add-document-policy-js-profiling-header
        source: '/(.*)',
        headers: [
          {
            key: 'Document-Policy',
            value: 'js-profiling'
          }
        ]
      }
    ]
  },
  async rewrites() {
    return [
      ...browserApiRewrites(deploymentUrls.api, process.env.NEXT_PUBLIC_SAME_ORIGIN_API),
      /**
       * @see https://posthog.com/docs/advanced/proxy/nextjs
       */
      {
        source: '/ingest/static/:path*',
        destination: 'https://us-assets.i.posthog.com/static/:path*'
      },
      {
        source: '/ingest/:path*',
        destination: 'https://us.i.posthog.com/:path*'
      },
      {
        source: '/ingest/decide',
        destination: 'https://us.i.posthog.com/decide'
      }
    ]
  },
  // This is required to support PostHog trailing slash API requests
  skipTrailingSlashRedirect: true
}

const sentryWebpackPluginOptions = {
  // silent: true, // Suppresses all logs
  // For all available options, see:
  // https://github.com/getsentry/sentry-webpack-plugin#options.
  authToken: process.env.SENTRY_AUTH_TOKEN,
  project: process.env.SENTRY_PROJECT,
  org: process.env.SENTRY_ORG,
  widenClientFileUpload: true,
  hideSourceMaps: true,
  telemetry: false,
  debug: false,
  tunnelRoute: '/monitoring-tunnel'
}

// Make sure adding Sentry options is the last code to run before exporting, to
// ensure that your source maps include changes from all other Webpack plugins
module.exports = withBundleAnalyzer(withSentryConfig(moduleExports, sentryWebpackPluginOptions))
