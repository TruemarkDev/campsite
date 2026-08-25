import { IncomingMessage, ServerResponse } from 'node:http'
import { Document, Hocuspocus } from '@hocuspocus/server'
import { TiptapTransformer } from '@hocuspocus/transformer'
import type { JSONContent } from '@tiptap/core'
import { generateJSON } from '@tiptap/html'
import * as Y from 'yjs'

import { getNoteExtensions, NOTE_SCHEMA_VERSION } from '@campsite/editor'

import { api } from './api'
import { Context } from './types'

const MAX_BODY_BYTES = 256 * 1024
const MAX_REQUESTS_PER_MINUTE = 30
const requestCounts = new Map<string, { count: number; resetAt: number }>()
const noteQueues = new Map<string, Promise<void>>()
const extensions = getNoteExtensions()

type EditMode = 'suggest' | 'direct'
type ContentFormat = 'html' | 'markdown'
type EditOperation =
  | { type: 'set_content'; content: string; format?: ContentFormat }
  | { type: 'append_section'; content: string; format?: ContentFormat }
  | { type: 'replace_section'; heading: string; content: string; format?: ContentFormat }
  | { type: 'stream'; chunks: string[]; format?: ContentFormat }

type AgentEditRequest = {
  note_id: string
  mode: EditMode
  operation: EditOperation
  instruction?: string
  schema_version?: number
}

class FacadeError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string
  ) {
    super(message)
  }
}

function sendJson(response: ServerResponse, status: number, body: object) {
  response.writeHead(status, { 'Content-Type': 'application/json' })
  response.end(JSON.stringify(body))
}

async function readJson(request: IncomingMessage): Promise<AgentEditRequest> {
  let size = 0
  const chunks: Buffer[] = []

  for await (const chunk of request) {
    const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk)

    size += buffer.byteLength
    if (size > MAX_BODY_BYTES) throw new FacadeError(413, 'payload_too_large', 'Request body is too large')
    chunks.push(buffer)
  }

  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    throw new FacadeError(400, 'invalid_json', 'Request body must be valid JSON')
  }
}

function bearerToken(request: IncomingMessage) {
  const authorization = request.headers.authorization ?? ''

  if (!authorization.startsWith('Bearer ') || authorization.length === 7) {
    throw new FacadeError(401, 'invalid_agent_sync_grant', 'A bearer grant is required')
  }

  return authorization.slice(7)
}

function enforceRateLimit(grantId: string) {
  const now = Date.now()
  const current = requestCounts.get(grantId)

  if (!current || current.resetAt <= now) {
    requestCounts.set(grantId, { count: 1, resetAt: now + 60_000 })
    return
  }

  current.count += 1
  if (current.count > MAX_REQUESTS_PER_MINUTE) {
    throw new FacadeError(429, 'agent_edit_rate_limited', 'Too many agent edits')
  }
}

async function markdownToHtml(markdown: string) {
  const baseUrl = process.env.STYLED_TEXT_API_URL || 'http://localhost:3002'
  const response = await fetch(`${baseUrl}/markdown_to_html`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ markdown, editor: 'note' })
  })

  if (!response.ok) throw new FacadeError(422, 'invalid_content', 'Markdown could not be parsed')

  const body = (await response.json()) as { html?: string }
  if (typeof body.html !== 'string') throw new FacadeError(422, 'invalid_content', 'Markdown could not be parsed')

  return body.html
}

async function parseContent(content: string, format: ContentFormat = 'html') {
  if (typeof content !== 'string' || content.length === 0 || content.length > MAX_BODY_BYTES) {
    throw new FacadeError(422, 'invalid_content', 'Content must be a non-empty bounded string')
  }

  const html = format === 'markdown' ? await markdownToHtml(content) : content

  try {
    const json = generateJSON(html, extensions)

    if (!json.content?.length) throw new Error('empty document')
    return json
  } catch {
    throw new FacadeError(422, 'invalid_content', 'Content is not valid note content')
  }
}

function suggestionAttrs(context: Context, request: AgentEditRequest, batchId: string) {
  return {
    actorId: context.actorId,
    actorType: 'agent',
    invokedBy: context.invokedBy,
    instruction: request.instruction,
    batchId,
    createdAt: new Date().toISOString()
  }
}

function markText(node: JSONContent, type: 'suggestionInsert' | 'suggestionDelete', attrs: object): JSONContent {
  const marked = { ...node }

  if (marked.type === 'text') marked.marks = [...(marked.marks ?? []), { type, attrs }]
  if (marked.content) marked.content = marked.content.map((child) => markText(child, type, attrs))

  return marked
}

function sectionRange(content: JSONContent[], heading: string) {
  const start = content.findIndex(
    (node) => node.type === 'heading' && node.content?.map((child) => child.text ?? '').join('') === heading
  )
  if (start < 0) throw new FacadeError(422, 'section_not_found', `Heading not found: ${heading}`)

  const level = Number(content[start].attrs?.level ?? 1)
  let end = content.length

  for (let index = start + 1; index < content.length; index += 1) {
    if (content[index].type === 'heading' && Number(content[index].attrs?.level ?? 1) <= level) {
      end = index
      break
    }
  }

  return { start, end }
}

function nextDocument(
  current: JSONContent,
  inserted: JSONContent,
  request: AgentEditRequest,
  context: Context,
  batchId: string
) {
  const operation = request.operation
  const content = current.content ?? []
  const insertedContent = inserted.content ?? []

  if (request.mode === 'direct') {
    if (operation.type === 'set_content') return inserted
    if (operation.type === 'append_section' || operation.type === 'stream') {
      return { ...current, content: [...content, ...insertedContent] }
    }

    const { start, end } = sectionRange(content, operation.heading)
    return { ...current, content: [...content.slice(0, start), ...insertedContent, ...content.slice(end)] }
  }

  const attrs = suggestionAttrs(context, request, batchId)
  const additions = insertedContent.map((node) => markText(node, 'suggestionInsert', attrs))

  if (operation.type === 'append_section' || operation.type === 'stream') {
    return { ...current, content: [...content, ...additions] }
  }

  if (operation.type === 'set_content') {
    return {
      ...current,
      content: [...content.map((node) => markText(node, 'suggestionDelete', attrs)), ...additions]
    }
  }

  const { start, end } = sectionRange(content, operation.heading)
  const removals = content.slice(start, end).map((node) => markText(node, 'suggestionDelete', attrs))

  return { ...current, content: [...content.slice(0, start), ...removals, ...additions, ...content.slice(end)] }
}

function replaceYDocument(document: Y.Doc, json: JSONContent) {
  const source = TiptapTransformer.toYdoc(json, 'default', extensions)
  const sourceFragment = source.getXmlFragment('default')
  const target = document.getXmlFragment('default')
  const nodes = sourceFragment.toArray().map((node) => node.clone())

  target.delete(0, target.length)
  target.insert(0, nodes)
}

function withAgentAwareness(document: Document, context: Context, callback: () => void) {
  const awareness = document.awareness as typeof document.awareness & {
    meta: Map<number, { clock: number; lastUpdated: number }>
  }
  let clientId = Math.floor(Math.random() * 0x7fffffff) + 1

  while (awareness.states.has(clientId)) clientId = (clientId % 0x7fffffff) + 1

  const state = {
    user: { id: context.actorId, name: context.actorName, isAgent: true }
  }
  const origin = { source: 'agent', grantId: context.grantId }

  awareness.states.set(clientId, state)
  awareness.meta.set(clientId, { clock: 0, lastUpdated: Date.now() })
  awareness.emit('change', [{ added: [clientId], updated: [], removed: [] }, origin])
  awareness.emit('update', [{ added: [clientId], updated: [], removed: [] }, origin])
  try {
    callback()
  } finally {
    awareness.states.delete(clientId)
    awareness.meta.set(clientId, { clock: 1, lastUpdated: Date.now() })
    awareness.emit('change', [{ added: [], updated: [], removed: [clientId] }, origin])
    awareness.emit('update', [{ added: [], updated: [], removed: [clientId] }, origin])
  }
}

async function queueForNote<T>(noteId: string, callback: () => Promise<T>) {
  const prior = noteQueues.get(noteId) ?? Promise.resolve()
  let release = () => {}
  const next = new Promise<void>((resolve) => {
    release = resolve
  })

  const queued = prior.then(() => next)

  noteQueues.set(noteId, queued)
  await prior
  try {
    return await callback()
  } finally {
    release()
    if (noteQueues.get(noteId) === queued) noteQueues.delete(noteId)
  }
}

async function applyEdit(instance: Hocuspocus<Context>, token: string, request: AgentEditRequest) {
  if (!request?.note_id || !request?.operation || !['suggest', 'direct'].includes(request.mode)) {
    throw new FacadeError(422, 'invalid_request', 'note_id, mode, and operation are required')
  }

  const agent = await api.agentSyncGrants
    .postAgentSyncGrantsVerify()
    .request({ note_id: request.note_id }, { headers: { Authorization: `Bearer ${token}` } })
  enforceRateLimit(agent.grant_id)

  return queueForNote(request.note_id, async () => {
    const loaded = instance.documents.get(request.note_id)
    if (request.mode === 'direct' && loaded && loaded.getConnectionsCount() > 0) {
      throw new FacadeError(409, 'active_editors', 'Direct edits are refused while editors are active')
    }

    const context: Context = {
      token,
      schemaVersion: request.schema_version ?? NOTE_SCHEMA_VERSION,
      organization: agent.organization,
      type: 'Note',
      actorType: 'agent',
      grantId: agent.grant_id,
      actorId: agent.actor_id,
      actorName: agent.actor_name,
      invokedBy: agent.invoked_by
    }
    const operation = request.operation
    const incoming = operation.type === 'stream' ? operation.chunks : [operation.content]
    if (incoming.length === 0) throw new FacadeError(422, 'invalid_content', 'A stream requires at least one chunk')

    const insertedDocuments = await Promise.all(incoming.map((content) => parseContent(content, operation.format)))
    const connection = await instance.openDirectConnection(request.note_id, context)
    const batchId = crypto.randomUUID()

    try {
      for (const inserted of insertedDocuments) {
        await connection.transact((document) => {
          const current = TiptapTransformer.fromYdoc(document, 'default') as JSONContent
          const next = nextDocument(current, inserted, request, context, batchId)

          withAgentAwareness(connection.document!, context, () => replaceYDocument(document, next))
        })
      }
    } finally {
      await connection.disconnect()
    }

    let attributionRecorded = true
    try {
      await api.agentSyncGrants
        .postAgentSyncGrantsNotesAttributions()
        .request(
          request.note_id,
          { batch_id: batchId, instruction: request.instruction },
          { headers: { Authorization: `Bearer ${token}` } }
        )
    } catch {
      attributionRecorded = false
    }

    return {
      batch_id: batchId,
      mode: request.mode,
      note_id: request.note_id,
      actor_id: agent.actor_id,
      invoked_by: agent.invoked_by,
      attribution_recorded: attributionRecorded
    }
  })
}

export async function handleAgentEditRequest(
  request: IncomingMessage,
  response: ServerResponse,
  instance: Hocuspocus<Context>
) {
  const path = new URL(request.url ?? '/', 'http://localhost').pathname
  if (!['/agent-edits', '/agent-edits/stream'].includes(path)) return false

  if (request.method !== 'POST') {
    sendJson(response, 405, { code: 'method_not_allowed' })
    return true
  }

  try {
    const token = bearerToken(request)
    const body = await readJson(request)

    if (path.endsWith('/stream') && body.operation?.type !== 'stream') {
      throw new FacadeError(422, 'invalid_operation', 'The stream endpoint requires a stream operation')
    }

    sendJson(response, 200, await applyEdit(instance, token, body))
  } catch (error) {
    if (error instanceof FacadeError) {
      sendJson(response, error.status, { code: error.code, message: error.message })
    } else {
      sendJson(response, 401, { code: 'invalid_agent_sync_grant' })
    }
  }

  return true
}

export const facadeInternals = { applyEdit, markText, nextDocument, replaceYDocument, sectionRange }
