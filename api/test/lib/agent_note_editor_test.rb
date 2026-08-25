# frozen_string_literal: true

require "test_helper"

class AgentNoteEditorTest < ActiveSupport::TestCase
  Response = Data.define(:status, :body)

  test "posts a bounded suggested edit with the grant bearer" do
    response = Response.new(status: 200, body: { batch_id: "batch-1" }.to_json)

    Faraday::Connection.any_instance.expects(:post).with(
      "/agent-edits",
      {
        note_id: "note-1",
        mode: :suggest,
        operation: { type: :append_section, content: "## Summary" },
        instruction: "Summarize the call",
        schema_version: 9,
      }.to_json,
      { "Content-Type" => "application/json", "Authorization" => "Bearer grant-token" },
    ).returns(response)

    result = AgentNoteEditor.new("grant-token").edit(
      note_id: "note-1",
      mode: :suggest,
      operation: { type: :append_section, content: "## Summary" },
      instruction: "Summarize the call",
      schema_version: 9,
    )

    assert_equal "batch-1", result[:batch_id]
  end

  test "uses the stream endpoint for stream operations" do
    response = Response.new(status: 200, body: { batch_id: "batch-1" }.to_json)

    Faraday::Connection.any_instance.expects(:post).with do |path, body, _headers|
      path == "/agent-edits/stream" && JSON.parse(body).dig("operation", "chunks") == ["one", "two"]
    end.returns(response)

    AgentNoteEditor.new("grant-token").edit(
      note_id: "note-1",
      mode: :suggest,
      operation: { type: :stream, chunks: ["one", "two"] },
    )
  end

  test "maps facade safety responses to typed errors" do
    Faraday::Connection.any_instance.stubs(:post).returns(Response.new(status: 409, body: { message: "active" }.to_json))

    assert_raises AgentNoteEditor::ActiveEditorsError do
      AgentNoteEditor.new("grant-token").edit(
        note_id: "note-1",
        mode: :direct,
        operation: { type: :set_content, content: "<p>Unsafe</p>" },
      )
    end
  end
end
