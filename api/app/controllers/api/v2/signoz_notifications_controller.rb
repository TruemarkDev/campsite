# frozen_string_literal: true

module Api
  module V2
    class SignozNotificationsController < BaseController
      include MarkdownEnrichable

      def create
        authorize(current_post, :create_comment?)

        comment = Comment.create_comment(
          params: {
            body_html: markdown_to_html(content_markdown)
          },
          subject: current_post,
          member: current_organization_membership,
          oauth_application: current_organization_membership ? nil : current_oauth_application
        )

        if comment.errors.empty?
          render_json(V2CommentSerializer, comment, status: :created)
        else
          render_unprocessable_entity(comment)
        end
      end

      private

      def current_post
        Post.find_by(public_id: ENV['SIGNOZ_ALERT_POST_ID'])
      end

      def content_markdown
        alerts = params[:alerts]
        alert  = alerts&.first || {}

        labels = alert.fetch("labels", {})
        annotations = alert.fetch("annotations", {})

        alertname = labels[:alertname]
        severity = labels[:severity]
        status_val = params[:status]

        summary = annotations[:summary]
        message = annotations[:message]
        description = annotations[:description]

        starts_at = alert[:startsAt]
        ends_at   = alert[:endsAt]

        fingerprint = alert[:fingerprint]

        external_url = params[:externalURL]

        content_markdown = <<~MD
          ### 🚨 #{alertname}

          **Severity:** #{severity}  
          **Status:** #{status_val}

          ---

          **Summary**  
          #{summary}

          **Message**  
          #{message}

          #{ description.present? ? "**Description**\n#{description}\n\n" : "" }

          **Started at:** #{starts_at}
          #{(ends_at.present? && ends_at != "0001-01-01T00:00:00Z") ? "**Ended at:** #{ends_at}" : ""}

          **Fingerprint:** `#{fingerprint}`

          #{ external_url.present? ? "**Source:** [View in SigNoz](#{external_url})" : "" }
        MD
      end
    end
  end
end
