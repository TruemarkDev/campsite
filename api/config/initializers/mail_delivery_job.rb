# frozen_string_literal: true

# Mail delivery jobs are enqueued from model callbacks that run inside the
# record's transaction (User#send_devise_notification is the signup path).
# ActiveJob enqueues immediately by default, so Sidekiq can pick a job up and
# look the record up before the transaction commits, and the mail then fails
# with RecordNotFound. Holding mail jobs until commit removes that race for
# every deliver_later in the app.
Rails.application.config.after_initialize do
  ActionMailer::MailDeliveryJob.enqueue_after_transaction_commit = true
end
