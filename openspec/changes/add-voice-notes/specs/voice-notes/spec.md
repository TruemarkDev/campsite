## ADDED Requirements

### Requirement: Audio attachments are automatically transcribed
When an `Attachment` whose `file_type` is an audio type (or a video with no
video track) is created on a post, comment, note, or message, the system
SHALL enqueue a background transcription job without any user action, using
a local speech-to-text engine that does not require an external API key by
default.

#### Scenario: Voice note attached to a post
- **WHEN** an audio attachment is created on a post (via the web upload flow
  or an MCP tool such as `upload_attachment` or `attach_file`)
- **THEN** the system enqueues a transcription job for that attachment and
  sets its transcription status to `pending`

#### Scenario: Non-audio attachment is not transcribed
- **WHEN** an image, video-with-audio, or link attachment is created
- **THEN** the system does not enqueue a transcription job for it and its
  transcription status remains unset

#### Scenario: Transcription succeeds
- **WHEN** the transcription job completes successfully for an audio
  attachment
- **THEN** the attachment's transcription status becomes `succeeded` and a
  plain-text transcript derived from the transcription output is available
  on the attachment

#### Scenario: Transcription fails
- **WHEN** the transcription job cannot produce a transcript after its
  configured retries (e.g. the local STT engine is unavailable or the audio
  is undecodable)
- **THEN** the attachment's transcription status becomes `failed`, the
  attachment and its parent post/comment/note/message remain otherwise
  usable, and no error is surfaced to the end user beyond the transcript
  being absent

### Requirement: Transcript is readable by MCP-connected agents
Any MCP tool response that includes attachment data SHALL include the
attachment's transcript (when available) and its transcription status, so an
agent can read the content of a voice note as text without decoding audio.

#### Scenario: Agent reads a post containing a voice note
- **WHEN** an agent calls `read_post` (or `read_note`, `read_messages`,
  `list_notifications`) on content that includes an audio attachment with a
  succeeded transcription
- **THEN** the returned attachment data includes a non-empty `transcript`
  field and a transcription status of `succeeded`

#### Scenario: Agent reads a post with a transcript still pending
- **WHEN** an agent calls a read tool on content that includes an audio
  attachment whose transcription has not yet completed
- **THEN** the returned attachment data includes a `null` or empty
  `transcript` field and a transcription status of `pending`

### Requirement: Agent can fetch a transcript by attachment id
The MCP server SHALL expose a tool that returns the transcript and
transcription status for a single attachment given its id, authorized the
same way as other read tools (the attachment's subject must be visible to
the calling agent's organization membership).

#### Scenario: Fetch transcript for an accessible attachment
- **WHEN** an agent calls `get_attachment_transcript` with the id of an
  audio attachment it is authorized to view
- **THEN** the tool returns the attachment's transcript (if transcription
  has succeeded), its transcription status, and identifying metadata (e.g.
  the parent subject type and id)

#### Scenario: Fetch transcript for an inaccessible attachment
- **WHEN** an agent calls `get_attachment_transcript` with the id of an
  attachment belonging to an organization the agent is not a member of, or a
  subject the agent is not authorized to view
- **THEN** the tool raises an authorization error and returns no transcript
  content

### Requirement: Agent can reply with synthesized speech
The MCP server SHALL expose a tool that synthesizes speech from agent-
supplied text and attaches the resulting audio to a post, comment, note, or
message, using a pluggable text-to-speech provider that defaults to a
provider requiring no API key.

#### Scenario: Agent sends a spoken reply using the default TTS provider
- **WHEN** an agent calls `speak_reply` with `text` and a target
  post/comment/note/message, and no TTS provider credentials are configured
- **THEN** the system synthesizes audio using the default free provider and
  creates an audio attachment on the target subject containing that audio

#### Scenario: Agent sends a spoken reply with an upgraded TTS provider configured
- **WHEN** an agent calls `speak_reply` and the deployment has valid
  ElevenLabs credentials configured as the active TTS provider
- **THEN** the system synthesizes audio using ElevenLabs and creates an
  audio attachment on the target subject containing that audio

#### Scenario: Configured upgraded provider is unavailable
- **WHEN** an agent calls `speak_reply`, the deployment is configured to use
  ElevenLabs, but the configured credentials are missing or invalid
- **THEN** the system falls back to the default free provider rather than
  failing the tool call, and still creates the audio attachment

### Requirement: Each agent identity has an independent voice
A Campsite user representing an AI agent SHALL be able to have its own
text-to-speech voice identity, distinct from other agents' voices, used by
default when that agent's identity calls `speak_reply` without an explicit
voice override.

#### Scenario: Agent speaks with its configured voice
- **WHEN** a user record has a `voice_id` set and that user's connected
  agent calls `speak_reply` without specifying a `voice_id` argument
- **THEN** the synthesized audio uses the voice identified by that user's
  `voice_id`

#### Scenario: Agent has no configured voice
- **WHEN** a user record has no `voice_id` set and that user's connected
  agent calls `speak_reply` without specifying a `voice_id` argument
- **THEN** the synthesized audio uses the active TTS provider's default
  voice
