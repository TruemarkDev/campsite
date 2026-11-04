# frozen_string_literal: true

require "test_helper"

class NoteAiEditorTest < ActiveSupport::TestCase
  setup do
    @note = create(:note)
  end

  test "returns structured replacement text" do
    response = stub(content: { "text" => "A concise sentence." })
    llm = mock

    Llm.expects(:new).returns(llm)
    llm.expects(:chat).with do |messages:, schema:, operation_type:, subject_type:, subject_id:|
      assert_equal(NoteAiEditor::RESPONSE_SCHEMA, schema)
      assert_equal("note_ai_edit", operation_type)
      assert_equal("Note", subject_type)
      assert_equal(@note.id, subject_id)
      assert_includes(messages.last[:content], "make concise")
      true
    end.returns(response)

    result = NoteAiEditor.new(
      note: @note,
      instruction: "make concise",
      selected_text: "A sentence that is too long.",
      before: "Before",
      after: "After",
    ).call

    assert_equal "A concise sentence.", result
  end

  test "rejects missing and oversized inputs before calling the provider" do
    Llm.expects(:new).never

    assert_raises(ArgumentError) do
      NoteAiEditor.new(note: @note, instruction: "", selected_text: "", before: "", after: "")
    end

    assert_raises(ArgumentError) do
      NoteAiEditor.new(
        note: @note,
        instruction: "edit",
        selected_text: "x" * (NoteAiEditor::MAX_SELECTED_TEXT_LENGTH + 1),
        before: "",
        after: "",
      )
    end
  end

  test "rejects a malformed structured response" do
    llm = stub(chat: stub(content: { "unexpected" => "value" }))

    Llm.stubs(:new).returns(llm)

    editor = NoteAiEditor.new(
      note: @note,
      instruction: "edit",
      selected_text: "text",
      before: "",
      after: "",
    )

    assert_raises(ArgumentError) { editor.call }
  end
end
