# frozen_string_literal: true

require "test_helper"

class SearchDocumentTest < ActiveSupport::TestCase
  setup do
    @member = create(:organization_membership)
    @org = @member.organization
  end

  test "prefixes, case folding, phrase preference and title-only queries" do
    exact = create(:post, member: @member, organization: @org, title: "Engineering plan")
    create(:post, member: @member, organization: @org, title: "Unrelated", description_html: "<p>Engineering plan</p>")
    results = Post.scoped_search(query: "ENGINEERING plan", organization: @org)
    assert_equal exact.id, results.first.id
    assert_includes Post.scoped_title_search(query: "engin", organization: @org).pluck(:id), exact.id
    assert_equal [exact.id], Post.scoped_title_search(query: "engineering", organization: @org).pluck(:id)
  end

  test "updates and deletes source and search documents in the same transaction" do
    post = create(:post, member: @member, organization: @org, title: "Original")
    Post.transaction do
      post.update!(title: "Changed")
      assert_equal [post.id], Post.scoped_search(query: "Changed", organization: @org).pluck(:id)
      raise ActiveRecord::Rollback
    end
    assert_empty Post.scoped_search(query: "Changed", organization: @org)
    assert_equal [post.id], Post.scoped_search(query: "Original", organization: @org).pluck(:id)
    post.reload.destroy!
    assert_empty SearchDocument.where(resource_type: "Post", resource_id: post.id)
  end

  test "escapes untrusted highlights and handles punctuation-only queries" do
    create(:post, member: @member, organization: @org, title: '<script>alert(1)</script> needle')
    result = Post.scoped_search(query: "needle", organization: @org).first
    assert_not_includes result[:highlight]['title.analyzed'].first, '<script>'
    assert_includes result[:highlight]['title.analyzed'].first, "<span class='search-highlight'>needle</span>"
    assert_nothing_raised { Post.scoped_search(query: "'&|:*", organization: @org) }
  end

  test "comments and author changes refresh searchable content without a queue" do
    post = create(:post, member: @member, organization: @org, title: "Original")
    comment = create(:comment, member: @member, subject: post, body_html: "<p>uniqueneedle</p>")
    assert_includes Post.scoped_search(query: "uniqueneedle", organization: @org).pluck(:id), post.id
    comment.discard!
    assert_empty Post.scoped_search(query: "uniqueneedle", organization: @org)
    @member.user.update!(name: "Distinctiveauthor")
    assert_includes Post.scoped_search(query: "Distinctiveauthor", organization: @org).pluck(:id), post.id
  end
  test "typo fallback and stable pagination" do
    post = create(:post, member: @member, organization: @org, title: "Engineering")
    assert_includes Post.scoped_search(query: "Enginering", organization: @org).pluck(:id), post.id
    older = create(:post, member: @member, organization: @org, title: "Older", created_at: 2.days.ago)
    first = Post.scoped_search(query: "", organization: @org, per_page: 1, page: 1, sort_by_date: true)
    second = Post.scoped_search(query: "", organization: @org, per_page: 1, page: 2, sort_by_date: true)
    assert_equal 2, first.total_count
    assert_equal [post.id], first.pluck(:id)
    assert_equal [older.id], second.pluck(:id)
  end

  test "highlight fragments are bounded and ignore stop words" do
    create(:post, member: @member, organization: @org, title: "the needle", description_html: "<p>#{'before ' * 100}needle #{'after ' * 100}</p>")
    result = Post.scoped_search(query: "the needle", organization: @org).first
    assert_equal "the <span class='search-highlight'>needle</span>", result[:highlight]['title.analyzed'].first
    assert_operator result[:highlight]['description.analyzed'].first.length, :<, 160
  end
  test "rebuild restores missing documents, removes orphans and is repeatable" do
    post = create(:post, member: @member, organization: @org, title: "Backfill")
    SearchDocument.where(resource_type: "Post", resource_id: post.id).delete_all
    SearchDocument.create!(resource_type: "Post", resource_id: 0, organization_id: @org.id, resource_created_at: Time.current)
    Rails.application.load_tasks unless Rake::Task.task_defined?("search:rebuild")
    2.times do
      Rake::Task["search:rebuild"].reenable
      capture_io { Rake::Task["search:rebuild"].invoke }
      assert_equal [post.id], Post.scoped_search(query: "Backfill", organization: @org).pluck(:id)
      assert_empty SearchDocument.where(resource_type: "Post", resource_id: 0)
    end
  end
  test "typo fallback searches body text without changing title-only mention search" do
    post = create(:post, member: @member, organization: @org, title: "Planning", description_html: "<p>The engineering team is ready</p>")
    assert_includes Post.scoped_search(query: "enginering", organization: @org).pluck(:id), post.id
    assert_empty Post.scoped_title_search(query: "enginering", organization: @org)
  end
  test "unchanged refresh preserves the physical row and changed content replaces it" do
    post = create(:post, member: @member, organization: @org, title: "Stable snapshot")
    scope = SearchDocument.where(resource_type: "Post", resource_id: post.id)
    before = scope.pick(Arel.sql("ctid::text"))
    post.refresh_search_document
    assert_equal before, scope.pick(Arel.sql("ctid::text"))
    post.update!(title: "Different snapshot")
    assert_not_equal before, scope.pick(Arel.sql("ctid::text"))
  end

  test "total count is lazy, accurate beyond the page, and memoized" do
    3.times { |i| create(:post, member: @member, organization: @org, title: "Laziness #{i}") }
    result = Post.scoped_search(query: "Laziness", organization: @org, limit: 1)
    assert_equal 1, result.length
    assert_query_count 1 do
      assert_equal 3, result.total_count
      assert_equal 3, result.total_count
    end
  end

  test "typo fallback handles repeated words, punctuation, unicode and body phrases" do
    post = create(:post, member: @member, organization: @org, title: "Unrelated", description_html: "<p>#{'engineering ' * 100}collaboration café</p>")
    assert_includes Post.scoped_search(query: "enginering", organization: @org).pluck(:id), post.id
    assert_includes Post.scoped_search(query: "café", organization: @org).pluck(:id), post.id
    assert_empty Post.scoped_search(query: "xylophonenomatch", organization: @org)
  end
end
