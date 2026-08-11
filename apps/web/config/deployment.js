const defaults = {
  web: 'https://camp.polo-apps.com',
  api: 'https://camp-api.polo-apps.com',
  auth: 'https://camp-auth.polo-apps.com',
  admin: 'https://camp-admin.polo-apps.com',
  sync: 'wss://camp-sync.polo-apps.com',
  cdn: 'https://camp-cdn.polo-apps.com',
  imgix: 'https://truecamp.imgix.net',
  objectStorage: 'https://hel1.your-objectstorage.com'
}

const envNames = {
  web: 'NEXT_PUBLIC_WEB_URL',
  api: 'NEXT_PUBLIC_API_URL',
  auth: 'NEXT_PUBLIC_AUTH_URL',
  admin: 'NEXT_PUBLIC_ADMIN_URL',
  sync: 'NEXT_PUBLIC_SYNC_URL',
  cdn: 'NEXT_PUBLIC_CDN_URL',
  imgix: 'NEXT_PUBLIC_IMGIX_URL',
  objectStorage: 'NEXT_PUBLIC_OBJECT_STORAGE_URL'
}

function buildDeploymentConfig(env = process.env) {
  const deploymentUrls = Object.fromEntries(
    Object.entries(defaults).map(([key, fallback]) => [key, env[envNames[key]] || fallback])
  )
  const deploymentOrigins = [...new Set(Object.values(deploymentUrls).map((value) => new URL(value).origin))]
  const deploymentImageDomains = [
    ...new Set(['web', 'api', 'cdn', 'imgix', 'objectStorage'].map((key) => new URL(deploymentUrls[key]).hostname))
  ]

  return { deploymentImageDomains, deploymentOrigins, deploymentUrls }
}

module.exports = { ...buildDeploymentConfig(), buildDeploymentConfig }
