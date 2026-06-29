# frozen_string_literal: true

require "test_helper"

class MentionableTest < ActiveSupport::TestCase
  class TestClass
    include Mentionable
  end

  setup do
    @test_instance = TestClass.new
  end

  context "#render_html" do
    test "renders task lists with checked/unchecked, disabled checkboxes" do
      html = @test_instance.render_html("- [x] done\n- [ ] todo")

      assert_includes html, '<input type="checkbox" checked="" disabled="" /> done'
      assert_includes html, '<input type="checkbox" disabled="" /> todo'
    end

    test "renders fenced code blocks with language class and info string as data-meta, without syntax highlighting" do
      html = @test_instance.render_html("```ruby info string\nx = 1\n```")

      assert_includes html, 'class="language-ruby"'
      assert_includes html, 'data-meta="info string"'
      # comrak's syntax highlighter must stay disabled (no inline style spans).
      refute_includes html, "style=\"color"
      refute_includes html, "background-color"
    end

    test "renders strikethrough via the extension" do
      html = @test_instance.render_html("~~struck~~")

      assert_includes html, "<del>struck</del>"
    end

    test "autolinks bare URLs" do
      html = @test_instance.render_html("see www.example.com")

      assert_includes html, '<a href="http://www.example.com">www.example.com</a>'
    end

    test "renders GFM tables" do
      html = @test_instance.render_html("| a | b |\n|---|---|\n| 1 | 2 |")

      assert_includes html, "<table>"
      assert_includes html, "<th>a</th>"
      assert_includes html, "<td>1</td>"
    end

    test "passes raw HTML through (unsafe)" do
      html = @test_instance.render_html('before <div class="raw">raw</div> after')

      assert_includes html, '<div class="raw">raw</div>'
    end

    test "strips surrounding whitespace" do
      html = @test_instance.render_html("hello")

      assert_equal "<p>hello</p>", html
    end
  end
end
