# frozen_string_literal: true

module McpTools
  class EditNote < McpTool
    OPERATION_TYPES = ["set_content", "append_section", "replace_section"].freeze

    tool_name "edit_note"
    description "Safely edit a collaborative note body through the replica-coordinated sync facade. Requires write_note."
    input_schema(org_scoped_schema(
      properties: {
        note_id: { type: "string" },
        mode: { type: "string", enum: ["suggest", "direct"], description: "suggest adds reviewable marks; direct is rejected while humans edit." },
        operation_type: { type: "string", enum: OPERATION_TYPES },
        content: { type: "string", description: "HTML content for the operation." },
        heading: { type: "string", description: "Required for replace_section." },
        instruction: { type: "string", description: "Optional audit context." },
      },
      required: ["note_id", "mode", "operation_type", "content"],
    ))

    private

    def execute
      require_scope!("write_note")
      actor, organization, member = organization_context!
      note = organization.notes.kept.find_by!(public_id: input[:note_id])
      authorize!(actor, note, :update?)
      unless Flipper.enabled?(:ai_note_editing, user) || Flipper.enabled?(:ai_note_editing, organization)
        raise ToolError, "Collaborative agent editing is not enabled for this user or organization."
      end
      validate_operation!

      grant, token = AgentSyncGrant.issue!(
        note: note,
        organization_membership: member,
        actor_id: "mcp-#{context.token.application_id}",
        actor_name: "MCP agent for #{user.display_name}",
        expires_in: 5.minutes,
      )

      operation = { type: input[:operation_type].to_sym, content: input[:content] }
      operation[:heading] = input[:heading] if input[:heading].present?
      result = AgentNoteEditor.new(token).edit(
        note_id: note.public_id,
        mode: input[:mode].to_sym,
        operation: operation,
        instruction: input[:instruction],
      )
      data_response(result)
    rescue AgentNoteEditor::ActiveEditorsError => e
      error(e.message.presence || "A human editor is active.", code: "active_editors")
    rescue AgentNoteEditor::InvalidContentError => e
      error(e.message.presence || "The requested edit is invalid.", code: "invalid_content")
    rescue AgentNoteEditor::ConnectionFailedError, AgentNoteEditor::ServerError
      error("Collaborative editing is unavailable.", code: "agent_edit_coordination_unavailable")
    ensure
      grant&.revoke! if grant&.active?
    end

    def validate_operation!
      return unless input[:operation_type] == "replace_section" && input[:heading].blank?

      raise ToolError, "heading is required for replace_section."
    end
  end
end
