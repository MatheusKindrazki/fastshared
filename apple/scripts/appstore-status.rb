#!/usr/bin/env ruby
# encoding: utf-8
# WHY: one-off diagnostic — pulls the real submission state from App Store
# Connect (versions, builds, IAPs, agreement) so we can decide what's needed
# to resubmit after a rejection. Read-only. No mutations.

require "spaceship"

key_id    = ENV.fetch("APPSTORE_CONNECT_API_KEY_ID")
issuer_id = ENV.fetch("APPSTORE_CONNECT_API_KEY_ISSUER_ID")
key_path  = ENV.fetch("APPSTORE_CONNECT_API_KEY_PATH")
bundle_id = ENV["APPSTORE_BUNDLE_ID"] || "dev.kindrazki.fastshared"

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
  client = Spaceship::ConnectAPI.tunes_request_client
  res_builds = client.get("v1/builds", filter: { app: app.id }, sort: "-uploadedDate", limit: 5).body
  Array(res_builds["data"]).first(5).each do |b|
    attr = b["attributes"] || {}
    puts "  • v#{attr["version"]} processing=#{attr["processingState"]} uploaded=#{attr["uploadedDate"]} expired=#{attr["expired"]}"
  end
rescue => e
  puts "  error: #{e.message}"
end
puts

puts "=== In-App Purchases ==="
begin
  client = Spaceship::ConnectAPI.tunes_request_client
  res_iap = client.get("v1/apps/#{app.id}/inAppPurchasesV2").body
  Array(res_iap["data"]).each do |iap|
    attr = iap["attributes"] || {}
    puts "  • #{attr["productId"]} — state: #{attr["state"]} (#{attr["inAppPurchaseType"]})"
  end
rescue => e
  puts "  error: #{e.message}"
end
puts

puts "=== Subscriptions ==="
begin
  client = Spaceship::ConnectAPI.tunes_request_client
  res_grp = client.get("v1/apps/#{app.id}/subscriptionGroups").body
  Array(res_grp["data"]).each do |grp|
    gattr = grp["attributes"] || {}
    puts "Group: #{gattr["referenceName"]}"
    res_sub = client.get("v1/subscriptionGroups/#{grp["id"]}/subscriptions").body
    Array(res_sub["data"]).each do |s|
      sattr = s["attributes"] || {}
      puts "  • #{sattr["productId"]} — state=#{sattr["state"]} (#{sattr["subscriptionPeriod"] || '—'})"
    end
  end
rescue => e
  puts "  error: #{e.message}"
end
puts

puts "Done."
