## Context

Campsite (this fork) is a Rails 8.1 / MySQL(trilogy) / Sidekiq 8.1 monolith.
Attachments are S3 objects referenced by `Attachment` rows (`file_path` =
S3 key, `file_type` = MIME type), served through Imgix for images/video.
`Attachment#audio?` already exists (`file_type.starts_with?("audio")`, or a
no-video-track video), so audio is already a legal attachment on posts,
comments, notes, and messages via the existing REST upload flow and via the
MCP tools `create_upload` + `attach_file` / `upload_attachment` (Tier 3 MCP
change, unarchived but merged into `main`, per `api/app/mcp/mcp_tools/`).

The `attachments` table has carried `transcription_job_id`,
`transcription_job_status`, and `transcription_vtt` columns since migration
`20230426204217` (2023) — grep across `api/app` shows **zero** references to
them in current model/job/serializer code. They are orphaned schema from an
earlier attempt at attachment transcription that never shipped. This design
reuses them rather than adding new columns, on the theory that whatever
naming/shape decisions were made then are still reasonable and reusing them
avoids a second unused-column graveyard.

The one *working* transcription pipeline in the codebase today is
`CallRecording#transcription_vtt`, populated by
`ProcessCallRecordingTranscriptionJob`, which downloads an SRT produced by
the 100ms/OpenAI call-recording pipeline and converts it to VTT. That
pipeline is cloud-API-driven (100ms transcribes server-side) and orthogonal
to this change — voice notes are short, user- or agent-recorded clips
attached inline, not 100ms call recordings, and the whole point of this
change is to avoid a mandatory API key.

Sidekiq is already the only job system in the repo (`BaseJob` < `Sidekiq::Worker`,
queues `critical/default/background/within_30_minutes/searchkick/backfill`
in `api/config/sidekiq.yml`). `AttachmentDimensionsJob` is the closest
existing analog: it shells out to `FFMPEG::Movie` (via `streamio-ffmpeg`,
already a Gemfile dependency) against the attachment's public `url`, mutates
the `Attachment` row, and saves. The transcription job follows the same
shape.

This is a single-org, self-hosted deployment (Truemark's own Campsite), not
a multi-tenant SaaS feature — the design intentionally skips things a SaaS
version would need (per-org STT provider config, usage metering/billing,
horizontal STT worker autoscaling).

## Goals / Non-Goals

**Goals:**
- Any audio attachment gets transcribed automatically, no user action, no
  required external API key.
- Transcript is readable by an MCP-connected agent through tools that
  already exist (`read_post`, `read_note`, `read_messages`,
  `list_notifications`) by adding one field to the shared
  `AttachmentSerializer`, plus one small tool for the id-only case.
- An agent can reply with synthesized speech using the *same* attach-a-file
  path (`upload_attachment`) already shipped for artifacts — no new upload
  transport.
- Local-first STT with no mandatory API key; TTS defaults to a free provider
  but the design admits that provider is a cloud endpoint, not local
  compute, and documents that trade-off rather than hiding it.
- Runs on existing Sidekiq infra, no new deployable process.

**Non-Goals:**
- Realtime/streaming speech-to-speech (async voice notes only, matching the
  "OpenClaw pattern" — record, upload, transcribe, reply — from
  `notes/research/2026-07-18-mission-control-voice.md` §2).
- Multi-tenant STT/TTS provider selection per organization; this is a single
  org.
- Re-touching the `CallRecording` / 100ms video-call transcription pipeline.
- Speaker diarization, live captions, or a VTT viewer UI (VTT storage is
  reused as-is for potential future UI; only the derived plain-text
  `transcript` is newly exposed).
- Building a standalone STT/TTS microservice — if a future need (e.g.
  GPU-bound batch transcription) outgrows a Sidekiq job, that is a separate,
  later change.

## Decisions

### 1. STT engine: whisper.cpp (default), sherpa-onnx as a documented alternative
`whisper.cpp` is chosen as the default local engine: single static binary,
CPU-only inference viable for short voice notes (seconds to low minutes),
CLI (`whisper-cli -m <model> -f <wav> -owts`/`--output-srt`) that a Sidekiq
job can `Open3.capture3` without a Ruby binding dependency, no API key.
`sherpa-onnx` is noted as an alternative (used by the OpenClaw/ClawChat
reference pattern for its faster streaming decode) but whisper.cpp's
simpler single-binary CLI is the better fit for "process one short clip per
job" rather than a streaming pipeline. Both ship a small model (`ggml-base.en`
or similar, ~150 MB) that must be present on the Sidekiq worker host —
**not** vendored into the repo; documented as a deploy prerequisite (README +
Hatchbox provisioning note), the same way `streamio-ffmpeg` already assumes
a system `ffmpeg` binary is present rather than bundling one.

Alternative considered and rejected: OpenAI Whisper API (already has a
Rails credentials slot — `openai` — used for call/post summaries). Rejected
as the *default* because it reintroduces a mandatory API key and per-call
cost, which is exactly what this change is scoped to avoid; kept as a
possible future fallback provider behind the same `Stt::Service` interface
if local inference proves too slow on the Hatchbox worker box, but not built
in this change (YAGNI for a single-org deployment — add it only if local
STT turns out to be a problem in practice).

### 2. VAD: skip Silero VAD for v1, revisit if trimming matters
The reference pattern (research doc §2, §4) pairs local STT with Silero VAD
to trim silence before transcription. For v1, voice notes are short,
user-initiated clips (not a continuously-open mic), so the marginal value of
VAD trimming is low relative to the added dependency (an ONNX runtime + a
second local model). `TranscribeAttachmentJob` runs whisper.cpp directly on
the whole clip. If transcription latency/accuracy on real voice notes proves
VAD would help, add it as a follow-up — the job's structure (download →
preprocess → transcribe → save) has an obvious slot for a preprocessing
step.

### 3. Storage: reuse the existing `transcription_vtt` / `transcription_job_status` columns on `Attachment`
Confirmed via `api/db/schema.rb` and migration `20230426204217`. Add exactly
one new derived accessor, not a new column: `Attachment#transcript` strips
VTT timing/cue markup down to plain text (a small parser, same rough shape
as the existing `WEBVTT`-munging in `ProcessCallRecordingTranscriptionJob`,
inverted — strip rather than build). `transcription_job_status` becomes an
enum-ish string set to `"pending"` (set synchronously in the same
`after_create_commit` hook that already enqueues `AttachmentDimensionsJob`),
`"succeeded"`, or `"failed"`. `transcription_job_id` stores the Sidekiq JID
for debugging (`TranscribeAttachmentJob.perform_async` return value), mainly
useful for support/ops.

### 4. Enqueue trigger: extend `Attachment`'s existing `after_create_commit` hook
`Attachment#enqueue_dimensions_job` already fires on create for
image/video. Add a sibling `enqueue_transcription_job` in the same
`after_create_commit :broadcast_attachments_stale` chain, gated on
`audio?`. This matches the existing pattern exactly rather than introducing
a new callback style or an out-of-band poller.

### 5. Exposing transcripts to agents: extend the existing serializer + one new MCP tool, no new REST endpoint
Because `AttachmentSerializer` is shared between the REST API and every MCP
tool that returns attachments (`upload_attachment`, `attach_file`,
and any post/note/comment/message read path that eager-loads attachments),
adding `transcript` (nullable string) and `transcription_job_status` there
makes the transcript show up everywhere attachments already show up — no
tool-by-tool plumbing. `get_attachment_transcript(attachment_id)` is added
as a small convenience MCP tool for the one case the serializer path doesn't
cover well: an agent that only has an attachment id (e.g., extracted from a
Pusher/webhook payload or a notification) and wants to poll status without
re-fetching the whole parent post/note/thread. Mirrors the existing
`read_*` tool shape (`org_scoped_schema`, Pundit `:show?` on the resolved
subject).

### 6. TTS: provider-strategy service object, Edge-TTS default, ElevenLabs opt-in
`Tts::Service.call(text:, voice_id:)` dispatches to a provider chosen by
`Rails.application.credentials.dig(:tts, :provider)` (default `"edge"` if
unset). `EdgeTtsProvider` shells out to the `edge-tts` CLI (Python package,
wraps Microsoft's consumer Edge Read-Aloud endpoint) — **note this is a free
*cloud* endpoint, not local inference**; it requires outbound HTTPS but no
API key/account, which satisfies "free default" from the proposal without
overclaiming it as offline. `ElevenLabsProvider` calls the ElevenLabs REST
API using a new `elevenlabs` credentials key (absent by default; provider
selection falls back to Edge-TTS if credentials are missing even when
configured as the org's provider, logged as a warning rather than a hard
failure — appropriate for a single-org deployment where "silently degrade to
free" beats "agent reply fails"). Both providers return raw audio bytes;
`speak_reply` writes those bytes through the exact same S3-put + attachment-create
code path `UploadAttachment` already implements (extracted into a small
shared method, `AttachmentUploader.put_and_attach!`, called by both
`UploadAttachment` and the new `SpeakReply` tool, rather than duplicating
the S3-put logic).

### 7. Per-agent voice identity: `voice_id` column on `User`, not a new model
Per the Tier 1/2 MCP design, each agent that talks to Campsite over MCP is
its own Campsite `User` (real account, OAuth-scoped). A single nullable
`voice_id` string column on `users` is enough to give each agent a distinct
ElevenLabs voice (or Edge-TTS voice name) — `speak_reply` defaults `voice_id`
to `Current.user.voice_id` if the caller doesn't pass one explicitly. This
avoids a join table / voice-catalog model that a single-org deployment
doesn't need; if multi-voice-per-agent (e.g. mood-based voice switching)
becomes a real requirement later, that's a follow-up.

## Risks / Trade-offs

- **[Risk] whisper.cpp binary/model absent on the Hatchbox worker host** →
  Job fails fast with a clear error (`transcription_job_status = "failed"`),
  retried 3x by Sidekiq (matching `AttachmentDimensionsJob`'s
  `sidekiq_options retry: 3`), does not block the attachment itself (audio
  still uploads and plays; transcript is best-effort). Deploy runbook update
  documents the binary + model as a provisioning step, checked into
  `runbooks/` in devopsy separately if useful — out of scope for this repo's
  proposal but noted.
- **[Risk] Edge-TTS is an unofficial/reverse-engineered Microsoft endpoint**,
  not a documented public API — it can break without notice. → Provider
  abstraction (`Tts::Service`) makes swapping the default (e.g. to a local
  Piper TTS binary) a one-file change, not a redesign. ElevenLabs remains
  available as an immediate manual fallback if Edge-TTS breaks.
  Non-goal: building retry/circuit-breaker logic around Edge-TTS in v1 — if
  it's flaky in practice, that's the trigger to swap the default provider,
  not to add resilience machinery around a free unofficial endpoint.
- **[Risk] CPU-bound whisper.cpp inference contends with other `background`
  queue jobs** on shared Sidekiq worker capacity → Runs on the existing
  `background` queue (concurrency 5 in production per `config/sidekiq.yml`);
  if voice-note volume ever makes this a bottleneck, route
  `TranscribeAttachmentJob` to its own queue — trivial `sidekiq_options`
  change, deferred until it's an observed problem (single-org volume is
  expected to be low).
- **[Risk] Transcript leaks into search/notifications unexpectedly** once
  `AttachmentSerializer#transcript` exists → No behavior change to search
  indexing in this proposal (Elasticsearch indexing is out of scope); flagged
  as an explicit open question below rather than silently deciding either
  way.
- **[Trade-off] Reusing 2023-era column names/types** (`transcription_vtt`
  as VTT rather than a cleaner plain-text-first shape) instead of a fresh
  migration → Avoids a second orphaned migration and keeps a future VTT-based
  caption UI possible for free; cost is the extra `transcript` derivation
  step in the model instead of storing plain text directly. Acceptable for
  the scope of this change.

## Migration Plan

1. Ship the `voice_id` migration on `users` (additive, nullable, zero
   downtime).
2. Ship `Attachment#enqueue_transcription_job` + `TranscribeAttachmentJob` +
   serializer fields behind no flag — audio attachments already exist and
   are rare enough today (voice-note usage is new) that a feature flag is
   unnecessary; if whisper.cpp isn't provisioned yet on deploy, jobs simply
   fail/retry/exhaust harmlessly (attachment itself is unaffected).
3. Provision the whisper.cpp binary + model on the Sidekiq worker host
   (Hatchbox) before or shortly after deploy — sequencing is soft since
   failure is non-blocking.
4. Ship the two MCP tools + `Tts::Service` + `speak_reply` in the same
   change (no cross-deploy dependency between STT and TTS halves, but small
   enough to ship together per the proposal's scope).
5. **Rollback**: all additive (new column, new job, new serializer fields,
   new MCP tools). Rollback is disabling the two new MCP tool registrations
   and/or not enqueuing the transcription job (comment out the
   `after_create_commit` hook) — no data migration to reverse.

## Open Questions

- Should transcripts be indexed into Elasticsearch search (so "find that
  voice note about X" works)? Left out of this change; the `transcript`
  field exists on the model either way, so indexing it later is additive.
- Should `speak_reply` auto-fire on every agent text reply (OpenClaw's
  "inbound" modality-matching — speak only when the human sent voice), or
  stay purely opt-in (agent explicitly calls the tool)? This proposal ships
  it opt-in only (agent must call `speak_reply`); auto-triggering based on
  the human's input modality is a UX-policy decision for whichever
  orchestration layer (hermes/Agency 2.0 dispatcher) calls the MCP tools,
  not something to hardcode into Campsite itself.
- Where should the whisper.cpp/edge-tts binary provisioning live —
  Hatchbox build pack config, a `bin/setup`-style script, or documented
  manual step? Deferred to `tasks.md` as a docs task; pick the lightest
  option that works for a single Hatchbox box.
