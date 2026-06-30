## ADDED Requirements

### Requirement: File upload and attachment tools

The server SHALL expose a `create_upload` tool, a `attach_file` tool, and a
`upload_attachment` tool, all organization-scoped, that let a connected user attach a
file to a post or note via the same presigned-S3-upload and `Attachment` creation
path the REST API uses. (Comment and message attachments are set at creation time in
the REST API and are out of scope here.)

`create_upload` SHALL return presigned S3 POST fields and the object key for a given
mime type, writing nothing in Campsite, and SHALL require the `mcp` scope only.

`attach_file` SHALL create an `Attachment` from an uploaded file path (S3 key) and
file type and link it to a subject (post or note), authorizing the subject's
`:update?` policy and requiring the write scope matching the subject (`write_post` for
a post, `write_note` for a note).

`upload_attachment` SHALL accept an inline base64 file content plus file type and
subject, upload it server-side, and create and link the attachment in one call, under
the same scope and authorization as `attach_file`. It SHALL enforce a maximum inline
size and reject larger files with an error directing the caller to `create_upload` +
`attach_file`.

No tool SHALL delete or reorder attachments, and no tool SHALL bypass the subject's
Pundit policy.

#### Scenario: Agent mints an upload target

- **WHEN** a user calls `create_upload` with a mime type
- **THEN** presigned S3 POST fields and an object key are returned and nothing is
  created in Campsite

#### Scenario: Agent links an uploaded file to a post

- **WHEN** a user with `write_post` calls `attach_file` with a file path, file type,
  and a post subject they may update
- **THEN** an attachment is created on that post and returned via the attachment
  serializer

#### Scenario: Agent uploads a small artifact inline

- **WHEN** a user with the subject's write scope calls `upload_attachment` with inline
  base64 content under the size cap and a subject they may update
- **THEN** the file is uploaded server-side, an attachment is created and linked, and
  returned via the attachment serializer

#### Scenario: Oversized inline upload is rejected

- **WHEN** a user calls `upload_attachment` with content exceeding the inline size cap
- **THEN** the tool returns an error directing the caller to `create_upload` plus
  `attach_file` and creates nothing

#### Scenario: Attachment blocked without scope or authorization

- **WHEN** a user lacking the subject's write scope calls `attach_file`/`upload_attachment`,
  OR a user calls them for a subject their policy forbids updating
- **THEN** the tool returns a scope or authorization error and creates nothing
