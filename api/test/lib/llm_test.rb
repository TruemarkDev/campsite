# frozen_string_literal: true

require "test_helper"

class LlmTest < ActiveSupport::TestCase
  setup do
    @chat = RubyLLM.chat(model: "gemini-2.5-flash", provider: :gemini)
    RubyLLM.stubs(:chat).returns(@chat)
  end

  test "sends system turns as instructions and joins the remaining turns into one prompt" do
    stub_completion(content: "ok")

    Llm.new.chat(messages: [
      { role: "system", content: "Be terse." },
      { role: "user", content: "First." },
      { role: "user", content: "Second." },
    ])

    assert_equal [:system, :user], @chat.messages.map(&:role)
    assert_equal "Be terse.", @chat.messages.first.content
    assert_equal "First.\n\nSecond.", @chat.messages.last.content
  end

  test "drops blank turns and accepts a plain string prompt" do
    stub_completion(content: "ok")

    Llm.new.chat(messages: [
      { role: "system", content: "" },
      { role: "user", content: "Only this." },
    ])

    assert_equal [:user], @chat.messages.map(&:role)
    assert_equal "Only this.", @chat.messages.last.content

    @chat.messages.clear
    Llm.new.chat(messages: "Bare string.")

    assert_equal "Bare string.", @chat.messages.last.content
  end

  test "decodes structured output and reports token usage" do
    stub_completion(
      content: { text: "A concise sentence." }.to_json,
      tokens: RubyLLM::Tokens.new(input: 11, output: 3, cache_read: 7),
    )

    response = Llm.new.chat(messages: [{ role: "user", content: "edit" }], schema: { type: "object" })

    assert_equal({ "text" => "A concise sentence." }, response.parsed)
    assert_equal 11, response.usage.prompt_tokens
    assert_equal 3, response.usage.completion_tokens
    assert_equal 14, response.usage.total_tokens
    assert_equal 7, response.usage.cached_tokens
  end

  private

  def stub_completion(content:, tokens: nil)
    message = RubyLLM::Message.new(role: :assistant, content: content, tokens: tokens)
    @chat.stubs(:complete).returns(message)
  end
end
