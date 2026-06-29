# frozen_string_literal: true

require "test_helper"
require "test_helpers/oauth_test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  include OauthTestHelper

  ALL_SCOPES = "mcp read_organization read_user read_post read_project write_post write_message write_note write_project"

  setup do
    @org = create(:organization)
    @member = create(:organization_membership, :member, organization: @org)
    @user = @member.user
    @project = create(:project, organization: @org)
    @oauth_app = create(:oauth_application, owner: @user, name: "Claude")
    @token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: ALL_SCOPES)
  end

  # ---- handshake & auth (task 3.6) ----------------------------------------

  describe "authentication" do
    test "initialize handshake advertises protocol version, server info, and tools capability" do
      mcp_request(method: "initialize", params: { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "test", version: "1" } })

      assert_response :ok
      result = json_response["result"]
      assert result["protocolVersion"].present?
      assert_equal "campsite", result.dig("serverInfo", "name")
      assert result["capabilities"].key?("tools")
    end

    test "missing token returns 401 with a WWW-Authenticate resource_metadata pointer" do
      post("/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }, as: :json)

      assert_response :unauthorized
      assert_match(/resource_metadata=/, response.headers["WWW-Authenticate"])
    end

    test "invalid token returns 401" do
      mcp_request(method: "tools/list", token: "not-a-real-token")

      assert_response :unauthorized
    end

    test "valid token without the mcp scope is forbidden" do
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "read_organization")
      mcp_request(method: "tools/list", token: token.plaintext_token)

      assert_response :forbidden
      assert_equal "insufficient_scope", json_response["error"]
    end
  end

  # ---- tool discovery & dispatch (task 3.5 / 5.4) -------------------------

  describe "tools/list" do
    test "lists every registered tool with a name and input schema" do
      mcp_request(method: "tools/list")

      assert_response :ok
      tools = json_response.dig("result", "tools")
      names = tools.pluck("name")
      assert_includes names, "list_organizations"
      assert_includes names, "create_post"
      tools.each do |tool|
        assert tool["name"].present?
        assert tool["inputSchema"].present?
      end
    end

    test "advertises no destructive (delete) tool" do
      mcp_request(method: "tools/list")

      names = json_response.dig("result", "tools").pluck("name")
      assert_empty names.grep(/delete|destroy|remove/i)
    end
  end

  describe "tools/call errors" do
    test "unknown tool returns a JSON-RPC error, not a crash" do
      mcp_request(method: "tools/call", params: { name: "no_such_tool", arguments: {} })

      assert_response :ok
      assert json_response["error"].present?
    end
  end

  # ---- read tools (task 4.6) ----------------------------------------------

  describe "read tools" do
    test "list_organizations returns the user's organizations with slugs" do
      result = call_tool("list_organizations")

      assert_not tool_error?(result)
      slugs = structured_content(result)["data"].map { |m| m.dig("organization", "slug") }
      assert_includes slugs, @org.slug
    end

    test "list_posts returns published posts in the org" do
      posts = create_list(:post, 2, project: @project, organization: @org)

      result = call_tool("list_posts", { org_slug: @org.slug })

      assert_not tool_error?(result)
      ids = structured_content(result)["data"].pluck("id")
      assert_equal posts.map(&:public_id).sort, ids.sort
    end

    test "read_post returns a post and its comments" do
      post = create(:post, project: @project, organization: @org)
      create(:comment, subject: post, member: @member)

      result = call_tool("read_post", { org_slug: @org.slug, post_id: post.public_id })

      assert_not tool_error?(result)
      assert_equal post.public_id, structured_content(result).dig("post", "id")
      assert_equal 1, structured_content(result).dig("comments", "data").length
    end

    test "an org the user does not belong to is denied (no cross-org leakage)" do
      other_org = create(:organization)
      create_list(:post, 2, organization: other_org, project: create(:project, organization: other_org))

      result = call_tool("list_posts", { org_slug: other_org.slug })

      assert tool_error?(result)
      assert_match(/not a member/i, tool_text(result))
    end

    test "reading a post in a private project the user cannot see is denied (no Pundit bypass)" do
      private_project = create(:project, :private, organization: @org)
      post = create(:post, project: private_project, organization: @org)

      result = call_tool("read_post", { org_slug: @org.slug, post_id: post.public_id })

      assert tool_error?(result)
      assert_match(/not authorized/i, tool_text(result))
    end
  end

  describe "more read tools" do
    test "list_projects returns the org's projects" do
      result = call_tool("list_projects", { org_slug: @org.slug })

      assert_not tool_error?(result)
      ids = structured_content(result)["data"].pluck("id")
      assert_includes ids, @project.public_id
    end

    test "list_notes and read_note return a note the user owns" do
      note = create(:note, member: @member)

      list_result = call_tool("list_notes", { org_slug: @org.slug })
      assert_not tool_error?(list_result)
      assert_includes structured_content(list_result)["data"].pluck("id"), note.public_id

      read_result = call_tool("read_note", { org_slug: @org.slug, note_id: note.public_id })
      assert_not tool_error?(read_result)
      assert_equal note.public_id, structured_content(read_result)["id"]
    end

    test "list_message_threads and read_messages return the user's threads and messages" do
      thread = create(:message_thread, :dm, owner: @member)
      thread.send_message!(sender: @member, content: "hello world")

      threads_result = call_tool("list_message_threads", { org_slug: @org.slug })
      assert_not tool_error?(threads_result)
      thread_ids = structured_content(threads_result)["threads"].pluck("id")
      assert_includes thread_ids, thread.public_id

      messages_result = call_tool("read_messages", { org_slug: @org.slug, thread_id: thread.public_id })
      assert_not tool_error?(messages_result)
      assert_equal 1, structured_content(messages_result)["data"].length
    end

    test "search_posts returns authorized matches" do
      post = create(:post, project: @project, organization: @org, title: "searchable")
      Post.stubs(:scoped_search).returns(Post.where(id: post.id))

      result = call_tool("search_posts", { org_slug: @org.slug, q: "searchable" })

      assert_not tool_error?(result)
      assert_includes structured_content(result)["data"].pluck("id"), post.public_id
    end
  end

  # ---- write tools (task 5.5) ---------------------------------------------

  describe "write tools" do
    test "create_post creates a post under the user's identity" do
      assert_difference -> { @project.posts.count }, 1 do
        @result = call_tool("create_post", { org_slug: @org.slug, title: "From MCP", description_html: "<p>hi</p>", project_id: @project.public_id })
      end

      assert_not tool_error?(@result)
      post = @project.posts.order(:id).last
      assert_equal "From MCP", post.title
      assert_equal @member, post.member
    end

    test "add_comment adds a comment to a post" do
      post = create(:post, project: @project, organization: @org)

      assert_difference -> { post.comments.count }, 1 do
        @result = call_tool("add_comment", { org_slug: @org.slug, subject_type: "post", subject_id: post.public_id, body_html: "<p>nice</p>" })
      end

      assert_not tool_error?(@result)
    end

    test "add_reaction adds a reaction to a post" do
      post = create(:post, project: @project, organization: @org)

      assert_difference -> { post.reactions.count }, 1 do
        @result = call_tool("add_reaction", { org_slug: @org.slug, subject_type: "post", subject_id: post.public_id, content: "👍" })
      end

      assert_not tool_error?(@result)
    end

    test "a write tool is blocked when the token lacks the write_post scope" do
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp read_post")

      assert_no_difference -> { @project.posts.count } do
        @result = call_tool("create_post", { org_slug: @org.slug, title: "Nope", project_id: @project.public_id }, token: token.plaintext_token)
      end

      assert tool_error?(@result)
      assert_match(/write_post/, tool_text(@result))
    end

    test "create_post is denied when the user is not a member of the org" do
      other_org = create(:organization)
      other_project = create(:project, organization: other_org)

      result = call_tool("create_post", { org_slug: other_org.slug, title: "X", project_id: other_project.public_id })

      assert tool_error?(result)
    end
  end

  # ---- members, mentions & messaging --------------------------------------

  describe "members and messaging tools" do
    test "list_members returns members with ids and usernames" do
      other = create(:organization_membership, :member, organization: @org)

      result = call_tool("list_members", { org_slug: @org.slug })

      assert_not tool_error?(result)
      ids = structured_content(result)["data"].pluck("id")
      assert_includes ids, @member.public_id
      assert_includes ids, other.public_id
    end

    test "add_comment expands <@member_id> mention shorthand into mention markup" do
      other = create(:organization_membership, :member, organization: @org)
      post = create(:post, project: @project, organization: @org)

      result = call_tool("add_comment", {
        org_slug: @org.slug,
        subject_type: "post",
        subject_id: post.public_id,
        body_html: "<p>hey <@#{other.public_id}> look</p>",
      })

      assert_not tool_error?(result)
      comment = post.comments.order(:id).last
      assert_match(/data-type="mention"/, comment.body_html)
      assert_match(/data-id="#{other.public_id}"/, comment.body_html)
    end

    test "send_message posts into an existing thread" do
      thread = create(:message_thread, :dm, owner: @member)

      assert_difference -> { thread.messages.count }, 1 do
        @result = call_tool("send_message", { org_slug: @org.slug, thread_id: thread.public_id, content: "<p>hi there</p>" })
      end

      assert_not tool_error?(@result)
    end

    test "create_message_thread starts a new chat with a first message" do
      other = create(:organization_membership, :member, organization: @org)

      @result = call_tool("create_message_thread", {
        org_slug: @org.slug,
        member_ids: [other.public_id],
        content: "<p>let's chat</p>",
      })

      assert_not tool_error?(@result)
      thread = MessageThread.find_by(public_id: structured_content(@result)["id"])
      assert_not_nil thread
      assert_equal 1, thread.messages.count
      assert_includes thread.organization_memberships, other
    end

    test "messaging is blocked without the write_message scope" do
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp read_organization")
      thread = create(:message_thread, :dm, owner: @member)

      assert_no_difference -> { thread.messages.count } do
        @result = call_tool("send_message", { org_slug: @org.slug, thread_id: thread.public_id, content: "<p>nope</p>" }, token: token.plaintext_token)
      end

      assert tool_error?(@result)
      assert_match(/write_message/, tool_text(@result))
    end
  end

  # ---- identity, notifications & notes ------------------------------------

  describe "whoami" do
    test "returns the connected user's identity" do
      result = call_tool("whoami", {})

      assert_not tool_error?(result)
      content = structured_content(result)
      assert_equal @user.public_id, content.dig("user", "id")
      assert_equal @user.username, content.dig("user", "username")
    end

    test "lists the user's member id for each organization they belong to" do
      result = call_tool("whoami", {})

      assert_not tool_error?(result)
      memberships = structured_content(result)["memberships"]
      entry = memberships.find { |m| m["org_slug"] == @org.slug }
      assert entry.present?, "expected a memberships entry for @org"
      assert_equal @org.name, entry["org_name"]
      assert_equal @member.public_id, entry["member_id"]
    end

    test "takes no arguments and does not require a write scope" do
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp")
      result = call_tool("whoami", {}, token: token.plaintext_token)

      assert_not tool_error?(result)
      assert_equal @user.public_id, structured_content(result).dig("user", "id")
    end
  end

  describe "list_notifications" do
    test "returns the user's inbox notifications" do
      notification = create(:notification, organization_membership: @member)

      result = call_tool("list_notifications", { org_slug: @org.slug })

      assert_not tool_error?(result)
      ids = structured_content(result)["data"].pluck("id")
      assert_includes ids, notification.public_id
    end

    test "filter: activity returns the activity feed without error" do
      create(:notification, organization_membership: @member)

      result = call_tool("list_notifications", { org_slug: @org.slug, filter: "activity" })

      assert_not tool_error?(result)
      assert_kind_of Array, structured_content(result)["data"]
    end

    test "filter: home applies the curated home_inbox scope without error" do
      create(:notification, organization_membership: @member)

      result = call_tool("list_notifications", { org_slug: @org.slug, filter: "home" })

      assert_not tool_error?(result)
      assert_kind_of Array, structured_content(result)["data"]
    end

    test "unread: true only returns unread notifications" do
      unread = create(:notification, organization_membership: @member)
      read = create(:notification, :read, organization_membership: @member)

      result = call_tool("list_notifications", { org_slug: @org.slug, unread: true })

      assert_not tool_error?(result)
      ids = structured_content(result)["data"].pluck("id")
      assert_includes ids, unread.public_id
      assert_not_includes ids, read.public_id
    end

    test "an org the user does not belong to is denied (no cross-org leakage)" do
      other_org = create(:organization)

      result = call_tool("list_notifications", { org_slug: other_org.slug })

      assert tool_error?(result)
      assert_match(/not a member/i, tool_text(result))
    end
  end

  describe "mark_notification_read" do
    it "marks an unread notification as read" do
      notification = create(:notification, organization_membership: @member)
      assert_nil notification.read_at

      result = call_tool("mark_notification_read", { org_slug: @org.slug, notification_id: notification.public_id })

      assert_not tool_error?(result)
      structured = structured_content(result)
      assert structured["ok"]
      assert_equal notification.public_id, structured["notification_id"]
      assert_not_nil notification.reload.read_at
    end

    it "returns an error for an unknown notification id" do
      result = call_tool("mark_notification_read", { org_slug: @org.slug, notification_id: "does-not-exist" })

      assert tool_error?(result)
    end
  end

  describe "create_note" do
    test "create_note creates a note for the connected member" do
      assert_difference -> { @member.notes.count }, 1 do
        @result = call_tool("create_note", { org_slug: @org.slug, title: "My note", description_html: "<p>hello</p>" })
      end

      assert_not tool_error?(@result)
      assert_equal "My note", @member.notes.last.title
    end

    test "create_note attaches the note to a project when project_id is given" do
      @result = call_tool("create_note", { org_slug: @org.slug, title: "Project note", project_id: @project.public_id })

      assert_not tool_error?(@result)
      assert_equal @project.id, @member.notes.last.project_id
    end

    test "create_note is blocked when the token lacks the write_note scope" do
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp read_organization")

      assert_no_difference -> { Note.count } do
        @result = call_tool("create_note", { org_slug: @org.slug, title: "Nope" }, token: token.plaintext_token)
      end

      assert tool_error?(@result)
      assert_match(/write_note/, tool_text(@result))
    end
  end

  describe "update_note" do
    test "updates a note's title as the connected user" do
      note = create(:note, member: @member, title: "Old title")

      @result = call_tool("update_note", { org_slug: @org.slug, note_id: note.public_id, title: "New title" })

      assert_not tool_error?(@result)
      assert_equal "New title", note.reload.title
      assert_equal "New title", structured_content(@result)["title"]
    end

    test "updating a note is blocked without the write_note scope" do
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp read_organization")
      note = create(:note, member: @member, title: "Untouched")

      @result = call_tool("update_note", { org_slug: @org.slug, note_id: note.public_id, title: "Nope" }, token: token.plaintext_token)

      assert tool_error?(@result)
      assert_match(/write_note/, tool_text(@result))
      assert_equal "Untouched", note.reload.title
    end
  end

  describe "resolve_post" do
    it "resolves a post" do
      post = create(:post, organization: @org, member: @member)

      result = call_tool("resolve_post", { org_slug: @org.slug, post_id: post.public_id })

      assert_not tool_error?(result)
      assert_predicate post.reload, :resolved?
      assert_not_nil structured_content(result)
    end

    it "records an optional resolve_html note" do
      post = create(:post, organization: @org, member: @member)

      result = call_tool("resolve_post", {
        org_slug: @org.slug,
        post_id: post.public_id,
        resolve_html: "<p>shipped</p>",
      })

      assert_not tool_error?(result)
      post.reload
      assert_predicate post, :resolved?
      assert_equal "<p>shipped</p>", post.resolved_html
    end

    it "unresolves a post when resolved is false" do
      post = create(:post, organization: @org, member: @member)
      post.resolve!(actor: @member, html: nil, comment_id: nil)
      assert_predicate post.reload, :resolved?

      result = call_tool("resolve_post", {
        org_slug: @org.slug,
        post_id: post.public_id,
        resolved: false,
      })

      assert_not tool_error?(result)
      assert_not_predicate post.reload, :resolved?
    end

    it "errors without the write_post scope" do
      post = create(:post, organization: @org, member: @member)
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp read_post")

      result = call_tool(
        "resolve_post",
        { org_slug: @org.slug, post_id: post.public_id },
        token: token.plaintext_token,
      )

      assert tool_error?(result)
      assert_match(/write_post/, tool_text(result))
    end
  end

  describe "update_post" do
    it "updates the post title" do
      post = create(:post, project: @project, organization: @org, member: @member, title: "Old title")

      @result = call_tool("update_post", { org_slug: @org.slug, post_id: post.public_id, title: "New title" })

      assert_not tool_error?(@result)
      assert_equal "New title", post.reload.title
    end

    it "updates the post body via description_html" do
      post = create(:post, project: @project, organization: @org, member: @member)

      @result = call_tool("update_post", { org_slug: @org.slug, post_id: post.public_id, description_html: "<p>updated body</p>" })

      assert_not tool_error?(@result)
      assert_includes post.reload.description_html, "updated body"
    end

    it "moves the post to another project" do
      post = create(:post, project: @project, organization: @org, member: @member)
      other_project = create(:project, organization: @org)

      @result = call_tool("update_post", { org_slug: @org.slug, post_id: post.public_id, project_id: other_project.public_id })

      assert_not tool_error?(@result)
      assert_equal other_project.id, post.reload.project_id
    end

    it "returns an error when the post does not exist" do
      @result = call_tool("update_post", { org_slug: @org.slug, post_id: "nonexistent", title: "x" })

      assert tool_error?(@result)
    end

    it "does not edit a draft (unpublished) post, matching the REST published-post scope" do
      draft = create(:post, :draft, project: @project, organization: @org, member: @member, title: "Draft")

      @result = call_tool("update_post", { org_slug: @org.slug, post_id: draft.public_id, title: "Hijacked" })

      assert tool_error?(@result)
      assert_equal "Draft", draft.reload.title
    end

    it "requires the write_post scope" do
      post = create(:post, project: @project, organization: @org, member: @member, title: "Untouched")
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp read_organization read_post")

      @result = call_tool("update_post", { org_slug: @org.slug, post_id: post.public_id, title: "Nope" }, token: token.plaintext_token)

      assert tool_error?(@result)
      assert_equal "Untouched", post.reload.title
    end
  end

  describe "reply_to_comment" do
    it "creates a threaded reply to a comment" do
      post = create(:post, project: @project, organization: @org)
      parent = create(:comment, subject: post, member: @member)

      result = call_tool("reply_to_comment", {
        org_slug: @org.slug,
        comment_id: parent.public_id,
        body_html: "<p>thanks for the feedback</p>",
      })

      assert_not tool_error?(result), tool_text(result)

      reply = Comment.find_by(public_id: structured_content(result)["id"])
      assert_equal parent.id, reply.parent_id
      assert_equal post.id, reply.subject_id
      assert_equal parent.public_id, structured_content(result)["parent_id"]
    end

    it "returns a tool error without the write_post scope" do
      post = create(:post, project: @project, organization: @org)
      parent = create(:comment, subject: post, member: @member)
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp read_post")

      result = call_tool(
        "reply_to_comment",
        { org_slug: @org.slug, comment_id: parent.public_id, body_html: "<p>nope</p>" },
        token: token.plaintext_token,
      )

      assert tool_error?(result)
    end

    it "does not reply to a comment in another organization" do
      other_org = create(:organization)
      other_member = create(:organization_membership, :member, organization: other_org)
      other_post = create(:post, organization: other_org, member: other_member)
      other_parent = create(:comment, subject: other_post, member: other_member)

      result = call_tool("reply_to_comment", {
        org_slug: @org.slug,
        comment_id: other_parent.public_id,
        body_html: "<p>cross org</p>",
      })

      assert tool_error?(result)
    end
  end

  describe "create_project" do
    test "create_project creates a project with the connected member as creator" do
      assert_difference -> { @org.projects.count }, 1 do
        @result = call_tool("create_project", { org_slug: @org.slug, name: "Launch Plan", description: "Q3 launch" })
      end

      assert_not tool_error?(@result)
      project = @org.projects.order(:id).last
      assert_equal "Launch Plan", project.name
      assert_equal @member.id, project.creator_id
      assert_equal "Launch Plan", structured_content(@result)["name"]
    end

    test "create_project honors the private flag" do
      @result = call_tool("create_project", { org_slug: @org.slug, name: "Secret", private: true })

      assert_not tool_error?(@result)
      assert @org.projects.order(:id).last.private?
    end

    test "create_project is blocked when the token lacks the write_project scope" do
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp read_organization")

      assert_no_difference -> { Project.count } do
        @result = call_tool("create_project", { org_slug: @org.slug, name: "Nope" }, token: token.plaintext_token)
      end

      assert tool_error?(@result)
      assert_match(/write_project/, tool_text(@result))
    end
  end

  describe "create_follow_up" do
    test "creates a follow-up on a post for the connected member" do
      post = create(:post, organization: @org, member: @member)

      result = call_tool("create_follow_up", {
        org_slug: @org.slug,
        subject_type: "post",
        subject_id: post.public_id,
        show_at: 1.hour.from_now.iso8601,
      })

      assert_not tool_error?(result)
      assert_equal 1, post.follow_ups.count
      follow_up = post.follow_ups.first
      assert_equal @member, follow_up.organization_membership
      assert_equal follow_up.public_id, structured_content(result)["id"]
    end

    test "creates a follow-up on a note for the connected member" do
      note = create(:note, member: @member)

      result = call_tool("create_follow_up", {
        org_slug: @org.slug,
        subject_type: "note",
        subject_id: note.public_id,
        show_at: 1.hour.from_now.iso8601,
      })

      assert_not tool_error?(result)
      assert_equal 1, note.follow_ups.count
      assert_equal @member, note.follow_ups.first.organization_membership
    end

    test "creates a follow-up on a comment for the connected member" do
      post = create(:post, organization: @org, member: @member)
      comment = create(:comment, subject: post, member: @member)

      result = call_tool("create_follow_up", {
        org_slug: @org.slug,
        subject_type: "comment",
        subject_id: comment.public_id,
        show_at: 1.hour.from_now.iso8601,
      })

      assert_not tool_error?(result)
      assert_equal 1, comment.follow_ups.count
      assert_equal @member, comment.follow_ups.first.organization_membership
    end

    test "is denied when the user is not a member of the org" do
      other_org = create(:organization)
      other_member = create(:organization_membership, :member, organization: other_org)
      other_post = create(:post, organization: other_org, member: other_member)

      result = call_tool("create_follow_up", {
        org_slug: other_org.slug,
        subject_type: "post",
        subject_id: other_post.public_id,
        show_at: 1.hour.from_now.iso8601,
      })

      assert tool_error?(result)
      assert_match(/not a member/i, tool_text(result))
    end

    test "does not require a write scope (mcp scope only)" do
      token = create(:access_token, resource_owner: @user, application: @oauth_app, scopes: "mcp read_post")
      post = create(:post, organization: @org, member: @member)

      result = call_tool(
        "create_follow_up",
        {
          org_slug: @org.slug,
          subject_type: "post",
          subject_id: post.public_id,
          show_at: 1.hour.from_now.iso8601,
        },
        token: token.plaintext_token,
      )

      assert_not tool_error?(result)
      assert_equal 1, post.follow_ups.count
    end
  end

  private

  def mcp_request(method:, params: nil, id: 1, token: nil)
    token ||= @token.plaintext_token
    body = { jsonrpc: "2.0", id: id, method: method }
    body[:params] = params unless params.nil?
    post("/mcp", params: body, as: :json, headers: bearer_token_header(token))
  end

  def call_tool(name, arguments = {}, token: nil)
    mcp_request(method: "tools/call", params: { name: name, arguments: arguments }, token: token)
    json_response["result"]
  end

  def tool_error?(result)
    !!result["isError"]
  end

  def tool_text(result)
    result["content"].pluck("text").join("\n")
  end

  def structured_content(result)
    result["structuredContent"]
  end
end
