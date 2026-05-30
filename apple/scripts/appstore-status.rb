#!/usr/bin/env ruby
# WHY: one-off diagnostic — pulls the real submission state from App Store
# Connect (versions, builds, IAPs, agreement) so we can decide what's needed
# to resubmit after a rejection. Read-only. No mutations.

require "spaceship"

key_id    = ENV.fetch("APPSTORE_CONNECT_API_KEY_ID")
issuer_id = ENV.fetch("APPSTORE_CONNECT_API_KEY_ISSUER_ID")
key_path  = ENV.fetch("APPSTORE_CONNECT_API_KEY_PATH")
bundle_id = ENV["APPSTORE_BUNDLE_ID"] || "red.fastsha.fastshared"

token = Spaceship::ConnectAPI::Token.create(
  key_id: key_id,
  issuer_id: issuer_id,
  filepath: key_path
)
Spaceship::ConnectAPI.token = token

puts "=== App lookup ==="
app = Spaceship::ConnectAPI::App.find(bundle_id)
abort("App not found for bundle id #{bundle_id}") unless app
puts "App ID: #{app.id}"
puts "Name: #{app.name}"
puts "Bundle: #{app.bundle_id}"
puts "Primary locale: #{app.primary_locale}"
puts

%w[IOS MAC_OS].each do |platform|
  puts "=== Platform: #{platform} ==="

  edit = app.get_edit_app_store_version(platform: platform)
  if edit
    puts "[Edit version] #{edit.version_string} — state: #{edit.app_store_state}"
    puts "  Release type: #{edit.release_type}"
    puts "  Created: #{edit.created_date}"
    build = edit.build
    if build
      puts "  Build attached: #{build.version} (#{build.uploaded_date})"
      puts "  Build processing state: #{build.processing_state}"
      puts "  Build expired: #{build.expired}"
    else
      puts "  ⚠️  No build attached to Edit version"
    end
  else
    puts "[Edit version] none"
  end

  live = app.get_live_app_store_version(platform: platform)
  if live
    puts "[Live version] #{live.version_string} — state: #{live.app_store_state}"
  else
    puts "[Live version] none (never published on this platform)"
  end

  # Last 3 submissions for context
  begin
    versions = app.get_app_store_versions(filter: { platform: platform }).first(5)
    puts "[Recent versions]"
    versions.each do |v|
      build_v = v.build&.version || "—"
      puts "  • #{v.version_string} (#{v.app_store_state}) build=#{build_v} created=#{v.created_date}"
    end
  rescue => e
    puts "[Recent versions] error: #{e.message}"
  end
  puts
end

puts "=== Latest builds (any platform, last 5) ==="
begin
  builds = Spaceship::ConnectAPI::Build.all(
    app_id: app.id,
    sort: "-uploadedDate",
    limit: 5
  )
  builds.each do |b|
    puts "  • v#{b.version} processing=#{b.processing_state} uploaded=#{b.uploaded_date} expired=#{b.expired}"
  end
rescue => e
  puts "  error: #{e.message}"
end
puts

puts "=== In-App Purchases ==="
begin
  iaps = Spaceship::ConnectAPI::AppStoreVersion # placeholder
  # IAPs live under app.get_in_app_purchases on newer spaceship; fall back if missing
  if app.respond_to?(:get_in_app_purchases_v2)
    iaps = app.get_in_app_purchases_v2
    iaps.each do |iap|
      puts "  • #{iap.product_id} — state: #{iap.state} (#{iap.in_app_purchase_type})"
    end
  elsif app.respond_to?(:get_in_app_purchases)
    iaps = app.get_in_app_purchases
    iaps.each do |iap|
      puts "  • #{iap.product_id} — state: #{iap.state}"
    end
  else
    puts "  (Spaceship version too old to enumerate IAPs)"
  end
rescue => e
  puts "  error: #{e.message}"
end
puts

puts "=== Subscriptions ==="
begin
  groups = app.get_subscription_groups
  groups.each do |grp|
    puts "Group: #{grp.reference_name}"
    subs = grp.get_subscriptions
    subs.each do |s|
      puts "  • #{s.product_id} — state=#{s.state} (#{s.subscription_period || '—'})"
    end
  end
rescue => e
  puts "  error: #{e.message}"
end
puts

puts "Done."
