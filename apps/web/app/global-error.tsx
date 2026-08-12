'use client'

// Catches render errors in App Router routes only (currently just app/api/*).
// Pages Router errors are still handled by pages/_error and ErrorBoundary.
import { useEffect } from 'react'
import * as Sentry from '@sentry/nextjs'

export default function GlobalError({ error }: { error: Error & { digest?: string } }) {
  useEffect(() => {
    Sentry.captureException(error)
  }, [error])

  return (
    <html>
      <body>
        <h2>Something went wrong.</h2>
      </body>
    </html>
  )
}
