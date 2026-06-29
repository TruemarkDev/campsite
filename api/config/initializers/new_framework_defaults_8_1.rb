# frozen_string_literal: true

# This file eases your Rails 7.1 -> 8.1 upgrade by enabling new framework
# defaults one at a time, while `config.load_defaults` in config/application.rb
# stays at 7.1.
#
# Uncomment each line as you verify the new behavior is safe for this app,
# ideally one setting (or one group) per deploy. Once EVERY setting below is
# active and verified, bump `config.load_defaults` to 8.1 in
# config/application.rb and delete this file.
#
# Read more about each default at:
# https://guides.rubyonrails.org/configuring.html#results-of-config-load-defaults

###
# Rails 7.2 defaults
###

# Enable YJIT for production-grade performance. NOTE: this app already enables
# YJIT unconditionally via config/initializers/enable_yjit.rb. The 8.1 default
# is `!Rails.env.local?` (off in dev/test). Reconcile the two when flipping the
# 8.1 YJIT line below, then remove enable_yjit.rb.
# Rails.application.config.yjit = true

# Decode PostgreSQL `date` columns into Ruby `Date` objects instead of strings.
# Rails.application.config.active_record.postgresql_adapter_decode_dates = true

# Validate that migration timestamps are reasonable (not in the future, etc.).
# Rails.application.config.active_record.validate_migration_timestamps = true

###
# Rails 8.0 defaults
###

# Apply ETag/Last-Modified conditional GET handling strictly per RFC 7232:
# prefer the ETag over Last-Modified when both are present.
Rails.application.config.action_dispatch.strict_freshness = true

# Set a global 1-second timeout for all regular expressions to mitigate ReDoS.
# Watch for legitimately slow regexes after enabling this.
# Regexp.timeout = 1

###
# Rails 8.1 defaults
###

# Disable YJIT in local (development/test) environments, where reloading and
# method redefinition (mocking) negate YJIT's benefit. See the 7.2 YJIT note
# above and config/initializers/enable_yjit.rb.
# Rails.application.config.yjit = !Rails.env.local?

# Stop HTML-escaping `<`, `>`, and `&` in JSON responses rendered by controllers.
Rails.application.config.action_controller.escape_json_responses = false

# Raise on path-relative redirects (e.g. `redirect_to "foo"`), which are
# ambiguous and unsafe; use a leading slash or full URL instead.
# Rails.application.config.action_controller.action_on_path_relative_redirect = :raise

# Raise when an implicit-order finder (`first`/`last`) is used on a model that
# has no defined order, instead of silently ordering by primary key.
# Rails.application.config.active_record.raise_on_missing_required_finder_order_columns = true

# Stop escaping the JS line separators U+2028/U+2029 in JSON encoded by
# ActiveSupport::JSON / `to_json`.
Rails.application.config.active_support.escape_js_separators_in_json = false

# Use the Ruby (vs. ERB) render dependency tracker for view caching.
Rails.application.config.action_view.render_tracker = :ruby

# Omit `autocomplete="off"` on the hidden field that form helpers emit
# alongside checkboxes/collection inputs.
Rails.application.config.action_view.remove_hidden_field_autocomplete = true
