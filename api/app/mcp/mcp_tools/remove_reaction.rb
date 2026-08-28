# frozen_string_literal: true

module McpTools
  class RemoveReaction < McpTool
    tool_name "remove_reaction"
    description "Remove a reaction created by the connected member."
    input_schema(org_scoped_schema(properties: { reaction_id: { type: "string" } }, required: ["reaction_id"]))

    private

    def execute
      actor, _organization, member = organization_context!
      reaction = member.reactions.find_by!(public_id: input[:reaction_id])
      authorize!(actor, reaction, :destroy?)
      reaction.discard
      InvalidateMessageJob.perform_async(member.id, reaction.subject_id, "update-message") if reaction.subject.is_a?(Message)
      data_response({ removed: true, reaction_id: reaction.public_id })
    end
  end
end
