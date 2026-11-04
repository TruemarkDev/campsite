## Why

Agency 2.0 needs a voice channel for talking to and hearing back from AI
agents while away from a desk. A Telegram bridge was considered and rejected
in favor of Campsite itself: this fork is already self-hosted, already has
S3-backed attachment upload (images, video, and — per the `Attachment` model's
`audio?` predicate — audio), and already exposes an MCP server (`api/app/mcp`)
that lets agents read and write posts, notes, messages, and attachments as a
normal connected user. What's missing is the audio round-trip: a voice-note
attachment currently just sits as an opaque blob (no text an agent can read
without decoding audio), and there is no way for an agent to talk back.

Notably, the `attachments` table already carries `transcription_job_id`,
`transcription_job_status`, and `transcription_vtt` columns (migration
`20230426204217_add_transcription_job_id_and_status_to_attachments.rb`, 2023) that are **currently unused by any model, job, or serializer** — dead
schema from an earlier, abandoned attempt at this exact feature. This change
finishes that work: wire a local-first STT worker to populate those columns,
and add a symmetric TTS path for agent replies.

## What Changes

- **Voice notes in, transcribed automatically.** When an audio attachment
  (`Attachment#audio?`) is created on a post, comment, note, or message, a new
  Sidekiq job transcribes it and writes the result back onto the existing
  `transcription_job_status` / `transcription_vtt` columns on `Attachment`.
  Transcription runs **locally, no API key required** — `whisper.cpp` (or
  `sherpa-onnx`) shelled out to from the job, following the same
  `streamio-ffmpeg`-shells-to-a-binary pattern the codebase already uses in
  `AttachmentDimensionsJob`. Silero VAD trims silence before transcription.
- **Transcript surfaced to agents as plain text**, not just VTT captions:
  `AttachmentSerializer` gains a `transcript` field (plain-text, derived from
  the VTT) so any existing MCP read tool (`read_post`, `read_note`,
  `read_messages`, `list_notifications`, etc.) that already serializes
  attachments picks it up automatically — no new read tool needed. A new MCP
  tool, `get_attachment_transcript`, covers the case where an agent only has
  an attachment id (e.g. from a webhook/notification payload) and needs the
  transcript directly, including a `pending`/`failed` status so the agent
  knows whether to retry.
- **Optional TTS for agent replies.** A pluggable text-to-speech service
  object (`Tts::Service`, provider-strategy pattern) with a free local/default
  provider (Edge-TTS, no key) and ElevenLabs as an opt-in upgrade path
  (`Rails.application.credentials.elevenlabs`, absent by default). Agents
  synthesize a reply through a new MCP tool, `speak_reply`, which runs TTS and
  reuses the existing `upload_attachment` code path to attach the resulting
  audio file to a post/comment/message/note — no new upload plumbing.
- **Per-agent voice identity.** Since each MCP-connected agent is already a
  distinct Campsite `User` (one Campsite account per agent, per the Tier 1/2
  MCP proposals), voice selection is a `voice_id` attribute on that `User`
  (new column, nullable, defaults to the TTS provider's default voice) rather
  than a new join table — one voice per agent identity, settable via a small
  admin/profile affordance, no multi-tenant voice-catalog machinery.
- **Not building:** no realtime speech-to-speech, no new video-call
  transcription (that path — `CallRecording#transcription_vtt` via
  100ms/OpenAI — is untouched and unrelated), no new standalone service (the
  work runs in the existing Sidekiq `background` queue), no multi-tenant
  voice catalog UI.

## Capabilities

### New Capabilities

- `voice-notes`: audio-attachment transcription (STT) and agent voice replies
  (TTS) as a Campsite-native capability — covers the Sidekiq transcription
  job, the `Attachment` transcript field/serializer exposure, the TTS service
  object, and the two new MCP tools (`get_attachment_transcript`,
  `speak_reply`).

### Modified Capabilities

- None. No `openspec/specs/` capability exists yet for `mcp-tools` or
  `attachments` (the MCP proposals that would define them —
  `add-mcp-server`, `add-mcp-tier-3` — are themselves still unarchived), so
  the two new MCP tools and the `AttachmentSerializer` field are described as
  part of the new `voice-notes` capability rather than as a delta against a
  capability that doesn't exist in `openspec/specs/` yet. When those MCP
  changes are archived, a future change should fold `get_attachment_transcript`
  / `speak_reply` into the canonical `mcp-tools` spec.

## Impact

- **DB migration**: add `voice_id` (string, nullable) to `users`. The
  transcription columns on `attachments` already exist — no migration needed
  there.
- **New files**: `api/app/jobs/transcribe_attachment_job.rb`,
  `api/app/services/stt/whisper_cpp_client.rb` (or `sherpa_onnx_client.rb`),
  `api/app/services/tts/service.rb` + provider strategies
  (`edge_tts_provider.rb`, `eleven_labs_provider.rb`),
  `api/app/mcp/mcp_tools/get_attachment_transcript.rb`,
  `api/app/mcp/mcp_tools/speak_reply.rb`.
- **Modified files**: `api/app/models/attachment.rb` (enqueue the
  transcription job on create, alongside the existing
  `enqueue_dimensions_job` hook; add a `transcript` accessor deriving plain
  text from `transcription_vtt`), `api/app/serializers/attachment_serializer.rb`
  (add `transcript`, `transcription_job_status`), `api/app/models/user.rb`
  (`voice_id`), `api/app/mcp/mcp_tool_registry.rb` (register the two new
  tools), `api/Gemfile` (no new Ruby gem required for STT/TTS — both are
  shelled-out local binaries; document required system packages in README).
- **Infra**: `whisper.cpp` (or `sherpa-onnx`) binary + a small local model
  must be present on the Sidekiq worker host (documented in README /
  deploy runbook, not vendored); Edge-TTS needs outbound HTTPS (it is a free
  Microsoft cloud endpoint, not a local model, despite requiring no API key —
  this trade-off is called out explicitly in design.md).
- **No new service**: runs as Sidekiq jobs on the existing `background` queue,
  not a new process/container.
