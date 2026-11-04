# frozen_string_literal: true

# Search supplies a bounded, relevance-ordered candidate relation. Select only
# identifiers before hydrating the returned window with serializer associations.
class RankedPagination
  attr_reader :results, :next_cursor

  def initialize(scope:, hydration_scope:, after: nil, limit: nil)
    @scope = scope
    @hydration_scope = hydration_scope
    @after = after
    @limit = CursorPagination.new(scope: scope, limit: limit).per_page
  end

  def run
    candidates = @scope.pluck(:id, :public_id)
    if @after.present?
      index = candidates.index { |_, public_id| public_id == @after }
      candidates = index ? candidates.drop(index + 1) : []
    end
    window = candidates.first(@limit)
    @next_cursor = window.last&.last if candidates.length > @limit
    ids = window.map(&:first)
    records = @hydration_scope.where(id: ids).index_by(&:id)
    @results = ids.filter_map { |id| records[id] }
    self
  end

  def prev_cursor
    nil
  end
end
