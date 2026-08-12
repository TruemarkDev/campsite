# frozen_string_literal: true

class HtmlTransform
  class Table < Base
    NODE_NAMES = ["table"].freeze

    def plain_text
      lines = rows.map { |cells| cells.join("\t") }

      lines.empty? ? "" : "\n\n#{lines.join("\n")}"
    end

    def markdown
      table_rows = rows(:markdown)
      return "" if table_rows.empty?

      column_count = table_rows.map(&:length).max
      normalized_rows = table_rows.map { |cells| cells.fill("", cells.length...column_count) }
      header = normalized_rows.first
      body = normalized_rows.drop(1)
      output = [markdown_row(header), markdown_row(Array.new(column_count, "---"))]

      output.concat(body.map { |cells| markdown_row(cells) })
      "\n\n#{output.join("\n")}"
    end

    private

    def rows(method = :plain_text)
      node.css("tr").map do |row|
        row.xpath("./th|./td").map do |cell|
          handler(cell).new(node: cell, context: context).public_send(method).strip
        end
      end.reject(&:empty?)
    end

    def markdown_row(cells)
      "| #{cells.map { |cell| cell.gsub("|", "\\|").gsub(/\s*\n\s*/, " ") }.join(" | ")} |"
    end
  end
end
