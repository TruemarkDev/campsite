import { Logger } from '@hocuspocus/extension-logger'
import { Server } from '@hocuspocus/server'
import * as Sentry from '@sentry/node'
import * as dotenv from 'dotenv'

import { createRedisAgentEditCoordination } from './agentEditCoordination'
import { api } from './api'
import { ConnectionAuthorization } from './connectionAuthorization'
import { database, getResource, sendVersionToConnections } from './database'
import { handleAgentEditRequest } from './facade'
import { createRedisExtension, disconnectRedisExtension, redisConnectionsReady, verifyRedisExtension } from './redis'
import { AuthenticationError, Context } from './types'

if (process.env.NODE_ENV === 'production') {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.NODE_ENV,
    tracesSampleRate: 0
  })
}

dotenv.config()

const redis = createRedisExtension()
const agentEditCoordination = createRedisAgentEditCoordination(redis)
const connectionAuthorization = new ConnectionAuthorization()

const server = new Server<Context>({
  port: parseInt(process.env.PORT || '9000', 10),

  async onAuthenticate(data): Promise<Context> {
    if (!data.token) {
      throw new AuthenticationError('no-token')
    }

    const schemaVersion = parseInt(data.requestParameters.get('schemaVersion') || '0', 10)
    const organization = data.requestParameters.get('organization')
    const type = data.requestParameters.get('type')
    const actorType = data.requestParameters.get('actorType') === 'agent' ? 'agent' : 'human'

    if (actorType === 'human' && !organization) {
      throw new AuthenticationError('invalid-type')
    }

    try {
      let agent

      if (actorType === 'agent') {
        if (type !== 'Note') throw new AuthenticationError('invalid-type')

        agent = await api.agentSyncGrants
          .postAgentSyncGrantsVerify()
          .request({ note_id: data.documentName }, { headers: { Authorization: `Bearer ${data.token}` } })
      }

      const resolvedOrganization = agent?.organization ?? organization
      if (!resolvedOrganization) throw new AuthenticationError('invalid-type')

      const state = await getResource({
        token: data.token,
        id: data.documentName,
        type,
        organization: resolvedOrganization,
        actorType
      })

      if (!state) {
        throw new AuthenticationError('invalid-type')
      }

      const document = data.instance.documents.get(data.documentName)

      if (document) sendVersionToConnections(document, state.description_schema_version)
      data.connectionConfig.readOnly = schemaVersion < state.description_schema_version

      return {
        token: data.token,
        schemaVersion,
        organization: resolvedOrganization,
        type,
        actorType,
        ...(agent && {
          grantId: agent.grant_id,
          actorId: agent.actor_id,
          actorName: agent.actor_name,
          invokedBy: agent.invoked_by
        })
      }
    } catch (error) {
      Sentry.setContext('document', {
        id: data.documentName,
        organization,
        type
      })
      Sentry.setContext('context', {
        schemaVersion: schemaVersion,
        actorType
      })
      Sentry.captureException(error)
      throw error
    }
  },

  async onTokenSync(data) {
    if (data.context.actorType === 'human') {
      try {
        const state = await getResource({
          token: data.token,
          id: data.documentName,
          type: data.context.type,
          organization: data.context.organization,
          actorType: 'human'
        })
        if (!state) throw new AuthenticationError('invalid-permission')
        data.connection.context.token = data.token
        return { token: data.token }
      } catch {
        // Refreshing an identity token must not retain revoked note access.
        throw new AuthenticationError('invalid-permission')
      }
    }

    try {
      const agent = await api.agentSyncGrants
        .postAgentSyncGrantsVerify()
        .request({ note_id: data.documentName }, { headers: { Authorization: `Bearer ${data.token}` } })

      const refreshed = {
        token: data.token,
        organization: agent.organization,
        grantId: agent.grant_id,
        actorId: agent.actor_id,
        actorName: agent.actor_name,
        invokedBy: agent.invoked_by
      }
      Object.assign(data.connection.context, refreshed)
      return refreshed
    } catch {
      throw new AuthenticationError('invalid-grant')
    }
  },

  async connected(data) {
    connectionAuthorization.watch(data.connection, data.documentName)
    if (data.context.actorType === 'human') {
      await agentEditCoordination.humanConnected(data.documentName, data.socketId)
    }
  },

  async onDisconnect(data) {
    connectionAuthorization.stopSocket(data.socketId, data.documentName)
    if (data.context.actorType === 'human') {
      await agentEditCoordination.humanDisconnected(data.documentName, data.socketId)
    }
  },

  async beforeSync(data) {
    await connectionAuthorization.ensure(data.connection, data.documentName)
  },

  async onRequest(data) {
    const path = new URL(data.request.url ?? '/', 'http://localhost').pathname
    if (path === '/up' && !redisConnectionsReady(redis)) {
      data.response.writeHead(503, { 'Content-Type': 'application/json' })
      data.response.end(JSON.stringify({ status: 'unavailable', dependency: 'redis' }))
      throw null
    }

    if (await handleAgentEditRequest(data.request, data.response, data.instance, agentEditCoordination)) throw null
  },

  async onDestroy() {
    connectionAuthorization.destroy()
    await agentEditCoordination.destroy()
  },

  extensions: [redis, database, new Logger()]
})

export async function startServer() {
  await verifyRedisExtension(redis)
  server.listen()
}

void startServer().catch((error) => {
  Sentry.captureException(error)
  console.error('Redis coordination startup failed', error)
  disconnectRedisExtension(redis)
  process.exitCode = 1
})
