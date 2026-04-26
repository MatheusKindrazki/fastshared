.PHONY: bootstrap ios backend-dev backend-test db-migrate db-generate lint fmt clean web-dev web-build web-deploy cli-test cli-build testflight testflight-ios testflight-macos testflight-doctor testflight-bootstrap appstore-doctor appstore-screenshots appstore-privacy appstore-metadata appstore-metadata-ios appstore-metadata-macos appstore-sync appstore-submit

BUNDLER_VERSION ?= 2.4.22
BUNDLE ?= bundle _$(BUNDLER_VERSION)_
APPLE_ENV = set -a && { [ ! -f ./.env.testflight ] || . ./.env.testflight; } && { [ ! -f ./.env.appstore.local ] || . ./.env.appstore.local; } && set +a

bootstrap:
	@command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
	@command -v pnpm >/dev/null 2>&1 || npm i -g pnpm
	cd backend && pnpm install

ios:
	cd apple && xcodegen generate
	open apple/FastShared.xcworkspace 2>/dev/null || open apple/FastShared.xcodeproj

backend-dev:
	cd backend && pnpm dev

backend-test:
	cd backend && pnpm test

db-migrate:
	cd backend && pnpm drizzle-kit migrate

db-generate:
	cd backend && pnpm drizzle-kit generate

lint:
	cd backend && pnpm lint
	cd apple && swiftformat --lint . || true

fmt:
	cd backend && pnpm format
	cd apple && swiftformat . || true

clean:
	rm -rf backend/node_modules backend/dist backend/.wrangler
	rm -rf cli/node_modules cli/dist cli/dist-release
	rm -rf apple/FastShared.xcodeproj apple/FastShared.xcworkspace
	rm -rf apple/build apple/DerivedData

web-dev:
	cd web && pnpm dev

web-build:
	cd web && pnpm build

web-deploy:
	cd web && pnpm build && pnpm dlx wrangler pages deploy dist --project-name fastshared-web

cli-test:
	cd cli && pnpm test

cli-build:
	cd cli && pnpm typecheck && pnpm test && pnpm build

# --- TestFlight ---------------------------------------------------------------
# First-time setup: `make testflight-bootstrap` (installs fastlane via bundler).
# Before uploading: put your App Store Connect API key details in
# apple/.env.testflight (see docs/ops/testflight-setup.md).

testflight-bootstrap:
	gem install bundler:$(BUNDLER_VERSION) --user-install || true
	cd apple && $(BUNDLE) config set --local path "vendor/bundle" && $(BUNDLE) install

testflight-doctor:
	cd apple && set -a && . ./.env.testflight && set +a && $(BUNDLE) exec fastlane ios doctor && $(BUNDLE) exec fastlane mac doctor

testflight:
	cd apple && set -a && . ./.env.testflight && set +a && $(BUNDLE) exec fastlane beta_all

testflight-ios:
	cd apple && set -a && . ./.env.testflight && set +a && $(BUNDLE) exec fastlane ios beta

testflight-macos:
	cd apple && set -a && . ./.env.testflight && set +a && $(BUNDLE) exec fastlane mac beta

# --- App Store metadata / submission ----------------------------------------
# `apple/.env.testflight` provides the App Store Connect API key. Optional
# App Review contact/submission fields live in `apple/.env.appstore.local`
# (copy from `apple/.env.appstore.example`). App Privacy must be completed
# manually in App Store Connect; Apple's privacy questionnaire is not covered by
# the App Store Connect API key flow.

appstore-doctor:
	cd apple && $(APPLE_ENV) && $(BUNDLE) exec fastlane store_doctor

appstore-screenshots:
	cd apple && $(APPLE_ENV) && $(BUNDLE) exec fastlane store_screenshots

appstore-privacy:
	cd apple && $(APPLE_ENV) && $(BUNDLE) exec fastlane store_privacy

appstore-metadata:
	cd apple && $(APPLE_ENV) && $(BUNDLE) exec fastlane store_metadata

appstore-metadata-ios:
	cd apple && $(APPLE_ENV) && $(BUNDLE) exec fastlane ios store_metadata

appstore-metadata-macos:
	cd apple && $(APPLE_ENV) && $(BUNDLE) exec fastlane mac store_metadata

appstore-sync:
	cd apple && $(APPLE_ENV) && $(BUNDLE) exec fastlane store_sync

appstore-submit:
	cd apple && $(APPLE_ENV) && $(BUNDLE) exec fastlane store_submit
