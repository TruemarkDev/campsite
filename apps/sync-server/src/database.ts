import { Database } from '@hocuspocus/extension-database'
import { Document } from '@hocuspocus/server'
import { TiptapTransformer } from '@hocuspocus/transformer'
import * as Sentry from '@sentry/node'
import { generateHTML, generateJSON } from '@tiptap/html'
import { fromUint8Array, toUint8Array } from 'js-base64'
import * as Y from 'yjs'

import { getNoteExtensions, resolveSuggestions } from '@campsite/editor'

import { api } from './api'
import { Context } from './types'

const extensions = getNoteExtensions()

export function sendVersionToConnections(document: Document, version: number) {
  document.getConnections().forEach((connection) => {
    const connectionSchemaVersion = connection.context.schemaVersion ?? 0

    // Update connections to readOnly if the schema version is lower than the current version
    connection.readOnly = connectionSchemaVersion < version

    // Send the schema version to the client
    connection.sendStateless(
      JSON.stringify({
        type: 'schema',
        version
      })
    )
  })
}

type GetResourceProps = {
  token: string
  id: string
  type: string | null
  organization: string
  actorType?: Context['actorType']
}

export async function getResource({ token, id, type, organization, actorType = 'human' }: GetResourceProps) {
  if (type === 'Note') {
    if (actorType === 'agent') {
      return api.agentSyncGrants.getAgentSyncGrantsNotesSyncState().request(id, {
        headers: { Authorization: `Bearer ${token}` }
      })
    }

    return api.organizations.getNotesSyncState().request(organization, id, {
      headers: { Authorization: `Bearer ${token}` }
    })
  }
}

export const database = new Database({
  /**
   * Fetch the document state from Campsite, or generate a new document from the existing
   * HTML if the document has never been edited before.
   */
  async fetch(data) {
    const context: Context = data.context

    const id = data.documentName
    const { organization, type } = context

    try {
      if (!organization) return new Uint8Array()

      const state = await getResource({ token: context.token, id, type, organization, actorType: context.actorType })

      if (!state) {
        return new Uint8Array()
      }

      sendVersionToConnections(data.document, state.description_schema_version)

      // If there's a state (a.k.a, it has been edited before), return it
      if (state.description_state) {
        return toUint8Array(state.description_state)
      }

      // Otherwise, generate a new state from the HTML
      const json = generateJSON(state.description_html, extensions)
      const ydoc = TiptapTransformer.toYdoc(json, 'default', extensions)

      return Y.encodeStateAsUpdate(ydoc)
    } catch (error) {
      Sentry.setContext('document', {
        id,
        organization,
        type
      })
      Sentry.setContext('context', {
        schemaVersion: context.schemaVersion,
        actorType: context.actorType,
        grantId: context.grantId
      })
      Sentry.captureException(error)
      throw error
    }
  },

  /**
   * Store the document state in Campsite.
   */
  async store(data) {
    const context: Context = data.lastContext

    const id = data.documentName
    const { organization, type } = context

    try {
      if (!organization) return

      // Generate a state from the Yjs document
      const state = Y.encodeStateAsUpdate(data.document)
      const dbDocument = fromUint8Array(state)

      // Generate HTML from the Yjs document
      const json = TiptapTransformer.fromYdoc(data.document, 'default')
      const html = generateHTML(resolveSuggestions(json, 'strip'), extensions)

      // Push the state (for Y.js) and the HTML (for our API) to Campsite
      const payload = {
        description_html: html,
        description_state: dbDocument,
        description_schema_version: context.schemaVersion
      }
      const requestParams = { headers: { Authorization: `Bearer ${context.token}` } }

      if (context.actorType === 'agent') {
        await api.agentSyncGrants.putAgentSyncGrantsNotesSyncState().request(id, payload, requestParams)
      } else {
        await api.organizations.putNotesSyncState().request(organization, id, payload, requestParams)
      }
    } catch (error) {
      Sentry.setContext('document', {
        id,
        organization,
        type
      })
      Sentry.setContext('context', {
        schemaVersion: context.schemaVersion,
        actorType: context.actorType,
        grantId: context.grantId
      })
      Sentry.captureException(error)
      throw error
    }
  }
})
