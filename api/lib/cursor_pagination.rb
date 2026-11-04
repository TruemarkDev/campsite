# frozen_string_literal: true

class CursorPagination
  DEFAULT_PER_PAGE = 50
  MAX_PER_PAGE = 100

  def initialize(options = {})
    (options || {}).to_hash.symbolize_keys!
    @scope = options[:scope]
    @direction = options[:before].present? ? :before : :after
    @cursor_id = options[@direction]
    @order = if options[:order].nil?
      { id: :asc }
    elsif options[:order].is_a?(Symbol)
      { id: options[:order] }
    elsif options[:order].is_a?(Hash)
      options[:order]
    else
      raise ArgumentError, "Invalid order: #{options[:order].inspect}"
    end
    @order[:id] ||= :asc
    validate_order!
    @limit = options[:limit] || DEFAULT_PER_PAGE
  end

  def run
    @results = if cursor_record
      where_parts = @order.map.with_index do |(column_name, order), index|
        prefix = @order.keys.first(index).index_with { |column| cursor_record[column] }
        relation = @scope.where(prefix)
        value = cursor_record[column_name]
        comparison = comparator(order: order)

        # MySQL sorts NULL before non-NULL values. Include the NULL tail when
        # walking descending results, and allow cursors within that tail.
        if value.nil?
          comparison == ">" ? relation.where.not(column_name => nil) : relation.none
        else
          condition = "#{qualified_column(column_name)} #{comparison} :value"
          condition += " OR #{qualified_column(column_name)} IS NULL" if comparison == "<"
          relation.where("(#{condition})", value: value)
        end
      end

      where_parts.reduce(&:or)
    else
      @scope
    end

    @order.each do |(column_name, order)|
      ordering = @scope.klass.arel_table[column_name].public_send(order)
      if @scope.connection.adapter_name == "PostgreSQL"
        ordering = ordering.public_send(order == :asc ? :nulls_first : :nulls_last)
      end
      @results = @results.order(ordering)
    end

    # load an additional item to see if there is a next page
    extended_per_page = per_page + 1

    @results = if @direction == :after
      @results.limit(extended_per_page)
    else
      @results.last(extended_per_page)
    end

    @results = @results.to_a

    @has_more = @results.size > per_page

    # remove the overflow item from the results page
    start_index = @direction == :before && @has_more ? 1 : 0
    @results = @results[start_index, per_page] || []

    self
  end

  attr_reader :results

  def hydrate!(scope)
    ids = @results.map(&:id)
    records_by_id = scope.where(id: ids).to_a.index_by(&:id)
    @results = ids.filter_map { |id| records_by_id[id] }
    self
  end

  delegate :table_name, to: :@scope

  def per_page
    n = @limit.to_i

    if n <= 0
      DEFAULT_PER_PAGE
    elsif MAX_PER_PAGE && MAX_PER_PAGE < n
      MAX_PER_PAGE
    else
      n
    end
  end

  def next_cursor
    @direction == :after && @has_more ? @results.last.public_id : nil
  end

  def prev_cursor
    @direction == :before && @has_more ? @results.first.public_id : nil
  end

  def cursor_record
    return unless @cursor_id

    @cursor_record ||= @scope.find_by(public_id: @cursor_id)
  end

  def comparator(order:)
    if order == :asc
      @direction == :after ? ">" : "<"
    else
      @direction == :after ? "<" : ">"
    end
  end

  def total_count
    @scope.size
  end

  private

  def qualified_column(column_name)
    [
      @scope.connection.quote_table_name(table_name),
      @scope.connection.quote_column_name(column_name),
    ].join(".")
  end

  def validate_order!
    valid_columns = @scope.klass.column_names

    @order.each do |column_name, direction|
      raise ArgumentError, "Invalid order column: #{column_name.inspect}" unless column_name.to_s.in?(valid_columns)
      raise ArgumentError, "Invalid order direction: #{direction.inspect}" unless direction.in?([:asc, :desc])
    end
  end
end
