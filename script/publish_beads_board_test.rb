# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "rbconfig"
require "socket"
require "tmpdir"
load File.expand_path("publish-beads-board", __dir__)

class BeadsBoardPublisherTest < Minitest::Test
  Status = Data.define(:success?)

  class Runner
    attr_reader :commands, :working_directories

    def initialize(outputs)
      @outputs = outputs
      @commands = []
      @working_directories = []
    end

    def capture3(*command, chdir:)
      @commands << command
      @working_directories << chdir
      key = command.drop(2).join(" ")
      value = @outputs.fetch(key)
      [value.is_a?(Array) ? value.shift : value, "", Status.new(true)]
    end
  end

  def test_collects_only_read_only_commands_and_strips_forbidden_fields
    runner = Runner.new(
      "context --json" => JSON.generate(project_id: "campsite.board", repo_root: "/private/repo/campsite", bd_version: "1.2.2", schema_version: "1"),
      "vc status --json" => JSON.generate(branch: "main", revision: "abc123"),
      "export" => JSON.generate([{ id: "campsite-4cl.1", title: "\e[31mBoard\e[0m", description: "secret", status: "open", priority: 1, issue_type: "feature", labels: ["api"], created_at: "2026-08-28T00:00:00Z", updated_at: "2026-08-28T01:00:00Z" }]),
      "ready --json --limit 0" => JSON.generate([{ id: "campsite-4cl.1" }]),
      "blocked --json" => "[]",
    )
    collector = BeadsBoardPublisher::Collector.new(beads_bin: "/usr/bin/bd", repository: "/private/repo", runner: runner)

    snapshot = collector.snapshot(source_id: "source-1", expected_source_project_id: "campsite.board")

    assert_equal "Board", snapshot.fetch("issues").first.fetch("title")
    refute snapshot.key?("repository_display_name")
    assert_equal "1.2.2", snapshot.fetch("beads_version")
    refute snapshot.fetch("issues").first.key?("description")
    assert_equal 64, snapshot.fetch("digest").length
    assert_equal [
      ["/usr/bin/bd", "--readonly", "context", "--json"],
      ["/usr/bin/bd", "--readonly", "vc", "status", "--json"],
      ["/usr/bin/bd", "--readonly", "export"],
      ["/usr/bin/bd", "--readonly", "ready", "--json", "--limit", "0"],
      ["/usr/bin/bd", "--readonly", "blocked", "--json"],
      ["/usr/bin/bd", "--readonly", "context", "--json"],
      ["/usr/bin/bd", "--readonly", "vc", "status", "--json"],
    ], runner.commands
    assert_equal ["/private/repo"] * 7, runner.working_directories
  end

  def test_fails_closed_on_conflicting_native_classification
    runner = Runner.new(
      "context --json" => JSON.generate(project_id: "campsite.board", repo_root: "/repo", bd_version: "1.2.2"),
      "vc status --json" => JSON.generate(branch: "main", revision: "abc123"),
      "export" => JSON.generate([{ id: "x.1", title: "X", status: "open", priority: 1, issue_type: "task", created_at: "2026-08-28T00:00:00Z", updated_at: "2026-08-28T01:00:00Z" }]),
      "ready --json --limit 0" => JSON.generate([{ id: "x.1" }]),
      "blocked --json" => JSON.generate([{ id: "x.1" }]),
    )

    assert_raises(BeadsBoardPublisher::Error) do
      BeadsBoardPublisher::Collector.new(beads_bin: "bd", repository: "/repo", runner: runner).snapshot(source_id: "source", expected_source_project_id: "campsite.board")
    end
  end

  def test_accepts_in_progress_issue_omitted_from_ready_and_blocked
    runner = Runner.new(
      "context --json" => JSON.generate(project_id: "campsite.board", repo_root: "/repo", bd_version: "1.2.2"),
      "vc status --json" => JSON.generate(branch: "main", commit: "abc123"),
      "export" => JSON.generate([{ id: "x.1", title: "Working", status: "in_progress", priority: 1, issue_type: "task", created_at: "2026-08-28T00:00:00Z", updated_at: "2026-08-28T01:00:00Z" }]),
      "ready --json --limit 0" => "[]",
      "blocked --json" => "[]",
    )

    snapshot = BeadsBoardPublisher::Collector.new(beads_bin: "bd", repository: "/repo", runner: runner).snapshot(source_id: "source", expected_source_project_id: "campsite.board")

    assert_equal "In progress", snapshot.fetch("issues").first.fetch("board_state")
  end

  def test_accepts_deferred_issue_omitted_from_ready_and_blocked
    runner = Runner.new(
      "context --json" => JSON.generate(project_id: "campsite.board", repo_root: "/repo", bd_version: "1.2.2"),
      "vc status --json" => JSON.generate(branch: "main", commit: "abc123"),
      "export" => JSON.generate([{ id: "x.1", title: "Later", status: "deferred", priority: 1, issue_type: "task", created_at: "2026-08-28T00:00:00Z", updated_at: "2026-08-28T01:00:00Z" }]),
      "ready --json --limit 0" => "[]",
      "blocked --json" => "[]",
    )

    snapshot = BeadsBoardPublisher::Collector.new(beads_bin: "bd", repository: "/repo", runner: runner).snapshot(source_id: "source", expected_source_project_id: "campsite.board")

    assert_equal "Deferred", snapshot.fetch("issues").first.fetch("board_state")
  end

  def test_executable_runs_one_shot_in_a_bare_environment
    publisher = File.expand_path("publish-beads-board", __dir__)
    assert File.executable?(publisher)

    Dir.mktmpdir do |directory|
      beads_bin = File.join(directory, "bd")
      File.write(beads_bin, <<~RUBY)
        #!/usr/bin/env ruby
        require "json"
        command = ARGV.drop(1)
        outputs = {
          ["context", "--json"] => { project_id: "campsite.board", repo_root: #{directory.inspect}, bd_version: "1.2.2", schema_version: "1" },
          ["vc", "status", "--json"] => { branch: "main", revision: "abc123" },
          ["export"] => [{ id: "campsite-4cl.1", title: "Board", status: "open", priority: 1, issue_type: "feature", labels: ["api"], created_at: "2026-08-28T00:00:00Z", updated_at: "2026-08-28T01:00:00Z" }],
          ["ready", "--json", "--limit", "0"] => [{ id: "campsite-4cl.1" }],
          ["blocked", "--json"] => [],
        }
        expected_directory = File.realpath(#{directory.inspect})
        abort "unexpected command" unless ARGV.first == "--readonly" && Dir.pwd == expected_directory && outputs.key?(command)
        puts JSON.generate(outputs.fetch(command))
      RUBY
      File.chmod(0o755, beads_bin)

      server = TCPServer.new("127.0.0.1", 0)
      request_body = nil
      server_thread = Thread.new do
        if IO.select([server], nil, nil, 5)
          socket = server.accept
          headers = +""
          headers << socket.readpartial(1024) until headers.include?("\r\n\r\n")
          head, request_body = headers.split("\r\n\r\n", 2)
          content_length = head[/Content-Length: (\d+)/i, 1].to_i
          request_body << socket.read(content_length - request_body.bytesize) if request_body.bytesize < content_length
          socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
          socket.close
        end
      end

      env = {
        "CAMPSITE_BEADS_OAUTH_TOKEN" => "test-token",
        "HOME" => directory,
        "PATH" => "#{RbConfig::CONFIG.fetch("bindir")}:/usr/bin:/bin",
      }
      stdout, stderr, status = Open3.capture3(
        env,
        publisher,
        "--api-base-url", "http://127.0.0.1:#{server.addr[1]}",
        "--org", "campsite",
        "--project-id", "project-1",
        "--source-id", "source-1",
        "--source-project-id", "campsite.board",
        "--repository", directory,
        "--beads-bin", beads_bin,
        unsetenv_others: true,
      )
      server_thread.join
      server.close

      assert status.success?, stderr
      assert_equal "Snapshot accepted\n", stdout
      assert_equal "source-1", JSON.parse(request_body).fetch("source_id")
      refute_includes request_body, directory
    end
  end

  def test_malformed_native_records_fail_with_safe_diagnostics
    invalid_outputs = [
      { "context --json" => "[]" },
      { "export" => "{broken}\n{also broken}" },
      { "export" => "[42]" },
      { "ready --json --limit 0" => "{}" },
      { "export" => JSON.generate([fixture_issue.merge(dependencies: [42])]) },
      { "export" => JSON.generate([fixture_issue.merge(status: "unsupported")]) },
    ]
    invalid_outputs.each do |overrides|
      error = assert_raises(BeadsBoardPublisher::Error) { collect(fixture_outputs.merge(overrides)) }
      refute_includes error.message, "/private/repo"
    end
  end

  def test_rejects_source_revision_change_during_collection
    error = assert_raises(BeadsBoardPublisher::Error) do
      collect(fixture_outputs.merge("vc status --json" => [JSON.generate(branch: "main", revision: "one"), JSON.generate(branch: "main", revision: "two")]))
    end
    assert_equal "Beads changed during collection; retry publication", error.message
  end

  def test_unicode_metadata_fits_the_api_byte_limit
    snapshot = collect(fixture_outputs.merge("export" => JSON.generate([fixture_issue.merge(title: "界" * 500)])))
    title = snapshot.fetch("issues").first.fetch("title")
    assert_operator title.bytesize, :<=, 500
    assert title.valid_encoding?
  end

  def test_http_responses_are_bounded_and_fail_closed
    [200, 401, 404, 422, 500].each do |code|
      server = TCPServer.new("127.0.0.1", 0)
      server_thread = Thread.new do
        socket = server.accept
        headers = +""
        headers << socket.readpartial(1024) until headers.include?("\r\n\r\n")
        socket.write("HTTP/1.1 #{code} Result\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
        socket.close
      end
      client = BeadsBoardPublisher::Client.new(api_base_url: "http://127.0.0.1:#{server.addr[1]}", org_slug: "fixture", project_id: "fixture", token: "fixture-token")
      if code == 200
        assert_equal({}, client.publish({}))
      else
        error = assert_raises(BeadsBoardPublisher::Error) { client.publish({}) }
        assert_equal "Campsite rejected the request (HTTP #{code})", error.message
      end
    ensure
      server_thread&.join(2)
      server&.close
    end
  end

  private

  def fixture_issue
    { id: "x.1", title: "Fixture", status: "open", priority: 1, issue_type: "task", created_at: "2026-08-28T00:00:00Z", updated_at: "2026-08-28T01:00:00Z" }
  end

  def fixture_outputs
    {
      "context --json" => JSON.generate(project_id: "fixture", project_name: "Fixture", bd_version: "1.2.2"),
      "vc status --json" => JSON.generate(branch: "main", revision: "one"),
      "export" => JSON.generate([fixture_issue]),
      "ready --json --limit 0" => JSON.generate([{ id: "x.1" }]),
      "blocked --json" => "[]",
    }
  end

  def collect(outputs)
    BeadsBoardPublisher::Collector.new(beads_bin: "bd", repository: "/private/repo", runner: Runner.new(outputs)).snapshot(source_id: "source", expected_source_project_id: "fixture")
  end
end
