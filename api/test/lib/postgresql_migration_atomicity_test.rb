# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class PostgresqlMigrationAtomicityTest < ActiveSupport::TestCase
  test "unsafe migrations remain blocked on both adapters" do
    adapter = ActiveRecord::Base.connection.adapter_name
    assert_equal adapter == "PostgreSQL" ? "18" : "8.4", StrongMigrations.target_version

    Dir.mktmpdir("campsite-unsafe-migration-") do |directory|
      File.write(File.join(directory, "20260924000001_remove_email_bounce_email.rb"), <<~RUBY)
        class RemoveEmailBounceEmail < ActiveRecord::Migration[8.1]
          def change
            remove_column :email_bounces, :email, :string
          end
        end
      RUBY

      error = assert_raises(StandardError) { ActiveRecord::MigrationContext.new(directory).up }
      assert_match(/Dangerous operation detected/, error.message)
      assert ActiveRecord::Base.connection.column_exists?(:email_bounces, :email)
    end
  end

  test "citext rejects case-only identity duplicates at the database" do
    skip "PostgreSQL schema contract" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"

    first = EmailBounce.create!(email: "PgIdentityProbe@example.test")
    assert_equal first, EmailBounce.find_by!(email: "pgidentityprobe@EXAMPLE.test")
    assert_raises(ActiveRecord::RecordNotUnique) do
      EmailBounce.transaction(requires_new: true) { EmailBounce.create!(email: "pgidentityprobe@example.test") }
    end
  end

  test "product log generated columns read from jsonb" do
    skip "PostgreSQL schema contract" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"

    device_info = {
      browser_name: "Brave", browser_version: "1", os_name: "macOS", os_version: "15",
      device_name: "Mac", device_type: "desktop", device_brand: "Apple",
      is_desktop_app: true, is_pwa: false, desktop_app_version: "2",
    }
    log = ProductLog.create!(subject: create(:user), log_ts: Time.current, name: "schema probe", device_info: device_info)
    assert_equal device_info.transform_values(&:to_s).stringify_keys,
      log.reload.attributes.slice(*device_info.keys.map { |key| "device_info_#{key}" }).transform_keys { |key| key.delete_prefix("device_info_") }
  end

  test "a failed migration rolls back its DDL and version row" do
    skip "PostgreSQL transaction contract" unless ActiveRecord::Base.connection.adapter_name == "PostgreSQL"

    version = "20260924000000"
    column = "pg_atomicity_probe"

    Dir.mktmpdir("campsite-pg-migration-") do |directory|
      File.write(File.join(directory, "#{version}_add_pg_atomicity_probe.rb"), <<~RUBY)
        class AddPgAtomicityProbe < ActiveRecord::Migration[8.1]
          def change
            add_column :email_bounces, :#{column}, :integer
            raise "deliberate migration failure"
          end
        end
      RUBY

      context = ActiveRecord::MigrationContext.new(directory)
      error = assert_raises(StandardError) { context.up }
      assert_match(/deliberate migration failure/, error.message)
      assert_not ActiveRecord::Base.connection.column_exists?(:email_bounces, column)
      assert_not ActiveRecord::Base.connection.select_value("SELECT 1 FROM schema_migrations WHERE version = '#{version}'")
    end
  end
end
