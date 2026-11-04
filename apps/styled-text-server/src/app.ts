import * as Sentry from '@sentry/node'
import bodyParser from 'body-parser'
import express from 'express'
import morgan from 'morgan'

import { htmlToSlack } from './html'
import { markdownToHtml } from './markdown'

const authToken = process.env.AUTHTOKEN

if (!authToken?.trim()) throw new Error('AUTHTOKEN must be configured')

export const app: express.Express = express()

if (process.env.NODE_ENV === 'production') {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    debug: process.env.NODE_ENV !== 'production',
    environment: process.env.NODE_ENV ?? 'development',
    tracesSampleRate: 0
  })
}

app.use(morgan('combined'))
app.use((req, res, next) => {
  if (req.path === '/up') return next()

  if (req.header('Authorization') != `Bearer ${authToken}`) {
    return res.status(401).json({ message: 'invalid token' })
  }

  next()
})

app.get('/up', (req, res) => {
  res.send('OK')
})

app.use(bodyParser.text({ limit: '5mb' }))
app.use(bodyParser.urlencoded({ limit: '5mb', extended: true }))

app.post('/html_to_slack', bodyParser.json(), (req, res) => {
  if (!req.is('*/json')) {
    return res.status(415).json({ message: 'request must be application/json' })
  }

  const { html } = req.body ?? {}

  if (typeof html !== 'string') {
    return res.status(400).json({ message: 'html must be a string' })
  }

  const blocks = htmlToSlack(html)

  res.json(blocks)
})

app.post('/markdown_to_html', bodyParser.json(), (req, res) => {
  if (!req.is('*/json')) {
    return res.status(415).json({ message: 'request must be application/json' })
  }

  const { markdown, editor } = req.body ?? {}

  if (!markdown) {
    return res.status(400).json({ message: 'markdown and editor are required' })
  }

  if (typeof markdown !== 'string') {
    return res.status(400).json({ message: 'markdown must be a string' })
  }

  res.json({ html: markdownToHtml(markdown, editor) })
})

// The error handler must be before any other error middleware and after all controllers.
Sentry.setupExpressErrorHandler(app, {
  shouldHandleError(error) {
    return !error.status || parseInt(`${error.status}`) >= 400
  }
})
