## 1. Data model

- [x] 1.1 Migration: add `voice_id` (string, nullable) to `users`
  (`bin/rails g migration AddVoiceIdToUsers voice_id:string`)
- [x] 1.2 Confirm no migration is needed for `attachments.transcription_job_id`,
  `transcription_job_status`, `transcription_vtt` — verify these columns are
  still present and unused on `main` before building on them (re-run the
  `create_table "attachments"` check in `api/db/schema.rb`)
- [x] 1.3 `Attachment#transcript` — plain-text accessor deriving from
  `transcription_vtt` (strip `WEBVTT` header + cue timing lines, join text
  lines); returns `nil` when `transcription_vtt` is blank
- [x] 1.4 `Attachment#enqueue_transcription_job` — new `after_create_commit`
  hook alongside the existing `enqueue_dimensions_job`, gated on `audio?`;
  sets `transcription_job_status = "pending"` and enqueues
  `TranscribeAttachmentJob`
- [x] 1.5 Model tests: `audio?` attachment enqueues the job and sets
  `pending` status on create; non-audio attachment does not; `#transcript`
  correctly strips a sample VTT fixture to plain text; `#transcript` is
  `nil` when `transcription_vtt` is blank

## 2. STT worker (local-first, no required API key)

- [x] 2.1 `Stt::WhisperCppClient` — service object wrapping a shelled-out
  `whisper.cpp` CLI invocation (`Open3.capture3`) against a local WAV file;
  raises a typed error on non-zero exit or missing binary/model
- [x] 2.2 `TranscribeAttachmentJob` (`Sidekiq::Worker`, `queue: "background"`,
  `retry: 3`, same shape as `AttachmentDimensionsJob`) — download the
  attachment's audio via `Down.download(attachment.url)`, convert to WAV via
  `streamio-ffmpeg` if needed (whisper.cpp expects 16kHz mono WAV), run
  `Stt::WhisperCppClient`, write the resulting VTT/text into
  `transcription_vtt`, set `transcription_job_status = "succeeded"` and
  `transcription_job_id` to the Sidekiq JID; on any error, set
  `transcription_job_status = "failed"` and re-raise so Sidekiq retries
- [x] 2.3 Job test: successful transcription updates the attachment; a
  stubbed whisper.cpp failure leaves the attachment `failed` and does not
  raise past retry exhaustion (mirrors `sidekiq_retries_exhausted` handling
  in `BaseJob`)
- [x] 2.4 Document the whisper.cpp binary + model as a deploy prerequisite
  (README "Others"-style section, and a note for the Hatchbox build/deploy
  hooks) — pick the lightest provisioning mechanism that works for one
  Hatchbox box (per design.md Open Questions)

## 3. Surface transcripts to agents

- [x] 3.1 `AttachmentSerializer`: add `transcript` (nullable string) and
  `transcription_job_status` (nullable string) fields
- [x] 3.2 `McpTools::GetAttachmentTranscript` — org-scoped MCP tool, resolves
  the attachment by public id, authorizes via the parent subject's `:show?`
  policy (reuse `ResolvesAttachmentSubject` / the same authorization shape as
  `read_post`), returns transcript + status + subject type/id
- [x] 3.3 Register `get_attachment_transcript` in `McpToolRegistry`
- [x] 3.4 Tests: `read_post`/`read_note`/`read_messages` responses include
  `transcript`/`transcription_job_status` for audio attachments;
  `get_attachment_transcript` happy path; authorization-denied path for an
  attachment in an org/subject the caller cannot see
- [x] 3.5 Update `api/docs/mcp_server.md` with the new tool and the
  transcript fields on attachment payloads

## 4. TTS for agent replies

- [x] 4.1 `Tts::Service` — provider-strategy dispatcher
  (`Rails.application.credentials.dig(:tts, :provider)`, default `"edge"`),
  `#call(text:, voice_id: nil)` returns `{ bytes:, content_type: }`
- [x] 4.2 `Tts::EdgeTtsProvider` — shells out to the `edge-tts` CLI (document
  as a deploy prerequisite alongside whisper.cpp); no credentials required
- [x] 4.3 `Tts::ElevenLabsProvider` — calls the ElevenLabs REST API using a
  new `elevenlabs` credentials key; falls back to `EdgeTtsProvider` (logging
  a warning, not raising) when configured but credentials are missing/invalid
- [x] 4.4 Extract `AttachmentUploader.put_and_attach!(subject:, bytes:,
  file_type:, name:)` from `McpTools::UploadAttachment`'s S3-put + attachment-create
  logic so it can be shared with the new tool without duplicating it; update
  `UploadAttachment` to call the extracted method
- [x] 4.5 `McpTools::SpeakReply` — org-scoped MCP tool, input `text` +
  `subject_type`/`subject_id` (+ optional `voice_id` override), requires the
  subject's write scope (same authorization shape as `upload_attachment`),
  calls `Tts::Service`, then `AttachmentUploader.put_and_attach!`
- [x] 4.6 Register `speak_reply` in `McpToolRegistry`
- [x] 4.7 `User#voice_id` — `speak_reply` defaults `voice_id` to
  `Current.user.voice_id` when the caller omits it
- [x] 4.8 Tests: `speak_reply` with default (Edge) provider creates an audio
  attachment; with ElevenLabs credentials configured, uses ElevenLabs;
  with ElevenLabs configured but invalid credentials, falls back to Edge
  without failing the call; agent-specific `voice_id` is passed to the
  provider when set on the calling user
- [x] 4.9 Update `api/docs/mcp_server.md` with the new tool and the
  `voice_id` field on `User`

## 5. Quality gates and close-out

- [x] 5.1 `bundle exec rubocop -A` on all new/changed Ruby files
- [x] 5.2 `bin/rails test` for the full changed-file set (models, jobs, mcp
  tools, serializers)
- [x] 5.3 `bin/rails db:migrate` locally to confirm the `voice_id` migration
  applies cleanly; update `api/db/schema.rb`
- [x] 5.4 Update `api/README.md`/deploy docs with the whisper.cpp + edge-tts
  binary prerequisites (single consolidated section, cross-referenced from
  tasks 2.4 and 4.2)
- [x] 5.5 `openspec validate add-voice-notes --strict` passes
- [x] 5.6 If tracked in beads, file/close the relevant `bd` issue(s) for this
  change and note the id(s) in the PR description
