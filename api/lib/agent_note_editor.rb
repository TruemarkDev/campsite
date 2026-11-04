# frozen_string_literal: true

class AgentNoteEditor
  class Error < StandardError; end
  class ConnectionFailedError < Error; end
  class UnauthorizedError < Error; end
  class ActiveEditorsError < Error; end
  class InvalidContentError < Error; end
  class ServerError < Error; end

  def initialize(token)
    @token = token
  end

  def edit(note_id:, mode:, operation:, instruction: nil, schema_version: nil)
    post(
      path: operation.fetch(:type).to_s == "stream" ? "/agent-edits/stream" : "/agent-edits",
      body: {
        note_id: note_id,
        mode: mode,
        operation: operation,
        instruction: instruction,
        schema_version: schema_version,
      }.compact,
    )
  end

  private

  def connection
    @connection ||= Faraday.new(url: Campsite.base_sync_server_url)
  end

  def post(path:, body:)
    response = connection.post(path, body.to_json, {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{@token}",
    })
    parsed = JSON.parse(response.body, symbolize_names: true)

    case response.status
    when 200
      parsed
    when 401
      raise UnauthorizedError
    when 409
      raise ActiveEditorsError, parsed[:message]
    when 422
      raise InvalidContentError, parsed[:message]
    else
      raise ServerError
    end
  rescue Faraday::ConnectionFailed
    raise ConnectionFailedError
  end
end
