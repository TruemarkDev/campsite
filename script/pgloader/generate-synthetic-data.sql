-- Synthetic-only fixtures for the disposable campsite-copy-mysql database.
-- Run after loading api/db/schema.rb into that database.
REPLACE INTO users (id, email, encrypted_password, public_id, created_at, updated_at, otp_enabled, otp_backup_codes)
VALUES (900000001, 'MiXeD+synthetic@example.invalid', '', 'synUser00001', '2026-09-24 12:34:56.123456', '2026-09-24 12:34:56.654321', 1, '{"z":[1,true,null],"a":{"emoji":"🧪"}}');

REPLACE INTO product_logs (id, log_ts, name, data, device_info, created_at, updated_at)
VALUES (900000001, '2026-09-24 12:34:56.123456', 'synthetic-fixture', '{"nested":{"b":2,"a":1},"text":"synthetic 🧪"}', '{"browser_name":"Synthetic","browser_version":"1.2.3","desktop_app_version":"4.5.6","device_brand":"Example","device_name":"Fixture","device_type":"desktop","is_desktop_app":"true","is_pwa":"false","os_name":"FixtureOS","os_version":"9.8"}', '2026-09-24 12:34:56.123456', '2026-09-24 12:34:56.654321');

REPLACE INTO organizations (id, name, slug, public_id, invite_token, created_at, updated_at)
VALUES (900000001, 'Synthetic 🧪', 'synthetic-fixture-900000001', 'synOrg000001', 'synthetic-invite-token-900000001', '2026-09-24 12:34:56.123456', '2026-09-24 12:34:56.654321');

REPLACE INTO attachments (id, public_id, file_path, file_type, created_at, updated_at)
VALUES (900000001, 'synAtt000001', 'synthetic/fixture-900000001', 'synthetic', '2026-09-24 12:34:56.123456', '2026-09-24 12:34:56.654321');
