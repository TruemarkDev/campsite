# frozen_string_literal: true

# Derived search data lives in the same database and transaction as its source.
class SearchDocument < ApplicationRecord
  HIGHLIGHT_STOP_WORDS = %w[a about above after again against all am an and any are aren't as at be because been before being below between both but by can't cannot could couldn't did didn't do does doesn't doing don't down during each few for from further had hadn't has hasn't have haven't having he he'd he'll he's her here here's hers herself him himself his how how's i i'd i'll i'm i've if in into is isn't it it's its itself let's me more most mustn't my myself no nor not of off on once only or other ought our ours ourselves out over own same shan't she she'd she'll she's should shouldn't so some such than that that's the their theirs them themselves then there there's these they they'd they'll they're they've this those through to too under until up very was wasn't we we'd we'll we're we've were weren't what what's when when's where where's which while who who's whom why why's with won't would wouldn't you you'd you'll you're you've your yours yourself yourselves].freeze
  HIGHLIGHT_FIELDS = %w[title comments_content description summary transcription].freeze

  UPDATE_COLUMNS = %w[organization_id fields title content resource_created_at].freeze
  # Rebuilds and repeated refreshes must not rewrite identical rows and GIN entries.
  CONFLICT_UPDATE = Arel.sql(<<~SQL.squish)
    organization_id = EXCLUDED.organization_id,
    fields = EXCLUDED.fields,
    title = EXCLUDED.title,
    content = EXCLUDED.content,
    resource_created_at = EXCLUDED.resource_created_at
    WHERE (search_documents.organization_id, search_documents.fields, search_documents.title,
      search_documents.content, search_documents.resource_created_at)
    IS DISTINCT FROM (EXCLUDED.organization_id, EXCLUDED.fields, EXCLUDED.title,
      EXCLUDED.content, EXCLUDED.resource_created_at)
  SQL


  Hit = Struct.new(:data) do
    def [](key) = data[key.to_sym]
    def to_h = data
    def id = self[:id]
    def public_id = self[:public_id]
  end

  class Results < Array
    def initialize(items, &total_count)
      super(items)
      @total_count = total_count
    end

    def total_count
      @total_count = @total_count.call if @total_count.respond_to?(:call)
      @total_count
    end
  end

  def self.search_resource(model, query:, organization:, limit: 250, user_id: nil, author_username: nil, project_public_id: nil, tag_name: nil, sort_by_date: false, per_page: nil, page: nil, title_only: false)
    scope = where(resource_type: model.name, organization_id: organization.id)
    scope = scope.where("fields->>'discarded_at' IS NULL") unless model == Call
    scope = scope.where("fields->>'has_recordings' = 'true'") if model == Call
    if project_public_id.present?
      project = organization.projects.find_by!(public_id: project_public_id)
      scope = scope.where("fields->>'project_id' = ?", project.id.to_s)
    end
    if author_username.present?
      user_id = organization.memberships.joins(:user).find_by!(user: { username: author_username }).user_id
    end
    scope = scope.where("fields->>'user_id' = ?", user_id.to_s) if user_id
    if tag_name.present?
      tag = organization.tags.find_by!(name: tag_name)
      scope = scope.where("fields->'tag_ids' @> ?::jsonb", [tag.id].to_json)
    end

    words = query.to_s.downcase.scan(/[[:alnum:]_]+/).first(32)
    rank = "0.0"
    fuzzy_rank = "0.0"
    unless words.empty?
      tsquery = connection.quote(words.map { |word| "'#{word}':*" }.join(" | "))
      tsquery = "to_tsquery('simple', #{tsquery})"
      predicate = title_only ? "title_vector @@ #{tsquery}" : "(title_vector @@ #{tsquery} OR content_vector @@ #{tsquery})"
      matching = scope.where(predicate)
      # Preserve typo tolerance for sparse results, using trigram indexes.
      # A LIMIT row-goal can make PostgreSQL scan the tenant for absent prefixes.
      # Materialize the indexed candidate plan before applying the two-hit probe.
      probe_sql = "WITH search_candidates AS MATERIALIZED (#{matching.select('1').to_sql}) SELECT * FROM search_candidates LIMIT 2"
      if connection.select_values(probe_sql).length < 2 && query.to_s.length >= 3
        quoted_query = connection.quote(query.to_s)
        fuzzy_predicate = title_only ? "title %> #{quoted_query}" : "(title %> #{quoted_query} OR strip(content_vector)::text %> #{quoted_query})"
        matching = scope.where("#{predicate} OR #{fuzzy_predicate}")
        fuzzy_rank = title_only ? "word_similarity(#{quoted_query}, title)" : "greatest(word_similarity(#{quoted_query}, title), word_similarity(#{quoted_query}, strip(content_vector)::text))"
      end
      scope = matching
      phrase = connection.quote("%#{sanitize_sql_like(query.to_s.downcase)}%")
      rank = "(#{fuzzy_rank} + 2 * ts_rank_cd(title_vector, #{tsquery}) + #{title_only ? '0' : "ts_rank_cd(content_vector, #{tsquery})"} + CASE WHEN lower(title) LIKE #{phrase} THEN 3 ELSE 0 END)"
    end
    order = sort_by_date ? "resource_created_at DESC, resource_id DESC" : "search_score DESC, resource_created_at DESC, resource_id DESC"
    size = (per_page || limit).to_i.clamp(1, 1000)
    rows = scope.select("search_documents.*, #{rank} AS search_score").order(Arel.sql(order)).limit(size).offset(([page.to_i, 1].max - 1) * size)
    items = rows.map do |row|
      data = row.fields.symbolize_keys.merge(_score: row[:search_score].to_f)
      highlights = {}
      unless title_only || words.empty?
        HIGHLIGHT_FIELDS.each do |field|
          value = row.fields[field]
          text = Array(value).join(" ")
          terms = words.select { |word| word.length >= 3 && HIGHLIGHT_STOP_WORDS.exclude?(word) }
          next if terms.empty? || !text.match?(/#{Regexp.union(terms)}/i)

          match = text.match(/#{Regexp.union(terms)}/i)
          width = field == 'title' ? 300 : 100
          start = [match.begin(0) - width / 3, 0].max
          text = text[start, width]
          escaped = ERB::Util.html_escape(text)
          # Escape before inserting fixed markup; no user HTML can become markup.
          highlights["#{field}.analyzed"] = [escaped.gsub(/#{Regexp.union(terms)}/i) { |match| "<span class='search-highlight'>#{match}</span>" }]
        end
      end
      Hit.new(data.merge(highlight: highlights))
    end
    Results.new(items) { scope.count }
  end
end
