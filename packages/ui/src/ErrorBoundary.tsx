import * as Sentry from '@sentry/react'
// eslint-disable-next-line no-restricted-imports
import { ErrorBoundaryProps, ErrorBoundary as ReactErrorBoundary } from 'react-error-boundary'

// react-error-boundary 6 widened onError's first argument to `unknown`.
const logError = (error: unknown) => {
  Sentry.captureException(error)
}

export const ErrorBoundary = (props: ErrorBoundaryProps) => <ReactErrorBoundary onError={logError} {...props} />
