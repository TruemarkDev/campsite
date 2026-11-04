describe('api configuration', () => {
  const originalNodeEnv = process.env.NODE_ENV
  const originalApiBaseUrl = process.env.API_BASE_URL

  afterEach(() => {
    vi.resetModules()
    process.env.NODE_ENV = originalNodeEnv

    if (originalApiBaseUrl === undefined) {
      delete process.env.API_BASE_URL
    } else {
      process.env.API_BASE_URL = originalApiBaseUrl
    }
  })

  it('uses the local API outside production', async () => {
    process.env.NODE_ENV = 'test'
    delete process.env.API_BASE_URL

    const { api } = await import('../api')

    expect(api.baseUrl).toBe('http://api.campsite.test:3001')
    expect((api as unknown as { baseApiParams: unknown }).baseApiParams).toEqual({
      format: 'json',
      headers: { 'Content-Type': 'application/json' }
    })
  })

  it('uses API_BASE_URL in production', async () => {
    process.env.NODE_ENV = 'production'
    process.env.API_BASE_URL = 'https://api.campsite.test'

    const { api } = await import('../api')

    expect(api.baseUrl).toBe('https://api.campsite.test')
  })

  it('fails closed when production API_BASE_URL is missing', async () => {
    process.env.NODE_ENV = 'production'
    delete process.env.API_BASE_URL

    await expect(import('../api')).rejects.toThrow('API_BASE_URL must be set in production')
  })
})
