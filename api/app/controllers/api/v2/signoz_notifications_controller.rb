# frozen_string_literal: true

module Api
  module V2
    class SignozNotificationsController < BaseController
      include MarkdownEnrichable

      def create
        post = current_post
        return head :not_found unless post

        authorize(post, :create_comment?)

        comment = Comment.create_comment(
          params: {
            body_html: markdown_to_html(content_markdown)
          },
          subject: post,
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
        @current_post ||= Post.find_by(public_id: ENV['SIGNOZ_ALERT_POST_ID'] || 'nkbiu6u38grf')
      end

      def content_markdown
        alerts = Array(params[:alerts])

        return "No alerts found" if alerts.empty?

        markdown_blocks = alerts.map do |alert|
          alert = alert

          labels = (alert[:labels] || {}).to_unsafe_h.with_indifferent_access
          annotations = (alert[:annotations] || {}).to_unsafe_h.with_indifferent_access

          alertname = labels[:alertname]
          severity = labels[:severity]
          status_val = params[:status]
          summary = annotations[:summary]
          message = annotations[:message]
          description = annotations[:description]
          starts_at = alert[:startsAt]
          ends_at = alert[:endsAt]
          fingerprint = alert[:fingerprint]
          external_url = params[:externalURL]

          <<~MD
            ### 🚨 #{alertname}

            **Severity:** #{severity}  
            **Status:** #{status_val}

            ---

            **Summary**  
            #{summary}

            **Message**  
            #{message}

            #{ description.present? ? "**Description**\n#{description}\n" : "" }

            **Started at:** #{starts_at}  
            #{(ends_at.present? && ends_at != "0001-01-01T00:00:00Z") ? "**Ended at:** #{ends_at}" : ""}

            **Fingerprint:** `#{fingerprint}`

            #{ external_url.present? ? "**Source:** [View in SigNoz](#{external_url})" : "" }
          MD
        end

        markdown_blocks.join("\n\n---\n\n")
      end
    end
  end
end
