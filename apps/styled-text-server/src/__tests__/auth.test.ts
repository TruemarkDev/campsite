import supertest from 'supertest'
import { afterEach, describe, expect, it, vi } from 'vitest'

afterEach(() => {
  vi.unstubAllEnvs()
  vi.resetModules()
})

describe('service authentication', () => {
  it.each([undefined, '', '   '])('refuses startup with token %s', async (token) => {
    vi.stubEnv('AUTHTOKEN', token)
    vi.resetModules()
    await expect(import('../app')).rejects.toThrow('AUTHTOKEN must be configured')
  })

  it('rejects missing and invalid credentials before parsing, but preserves health checks', async () => {
    vi.stubEnv('AUTHTOKEN', 'configured-test-token')
    vi.resetModules()
    const { app } = await import('../app')

    await supertest(app).get('/up').expect(200)
    for (const token of ['', 'Bearer undefined', 'Bearer wrong']) {
      await supertest(app)
        .post('/html_to_slack')
        .set('Authorization', token)
        .set('Content-Type', 'application/json')
        .send('{broken')
        .expect(401)
    }
    await supertest(app)
      .post('/html_to_slack')
      .auth('configured-test-token', { type: 'bearer' })
      .send({ html: '<p>Hello</p>' })
      .expect(200)
    for (const html of [undefined, 42, {}]) {
      await supertest(app)
        .post('/html_to_slack')
        .auth('configured-test-token', { type: 'bearer' })
        .send({ html })
        .expect(400)
    }
  })
})
