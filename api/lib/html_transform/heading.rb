# frozen_string_literal: true

class HtmlTransform
  class Heading < Base
    NODE_NAMES = %w[h1 h2 h3 h4 h5 h6].freeze

    def plain_text
      "\n\n#{children.map(&:plain_text).join}"
    end

    def markdown
      level = node.name.delete_prefix("h").to_i

      "\n\n#{"#" * level} #{children.map(&:markdown).join}"
    end
  end
end
