.PHONY: bootstrap ios backend-dev backend-test db-migrate db-generate lint fmt clean web-dev web-build web-deploy testflight testflight-ios testflight-macos testflight-doctor testflight-bootstrap

BUNDLER_VERSION ?= 2.4.22
BUNDLE ?= bundle _$(BUNDLER_VERSION)_

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
	rm -rf apple/FastShared.xcodeproj apple/FastShared.xcworkspace
	rm -rf apple/build apple/DerivedData

web-dev:
	cd web && pnpm dev

web-build:
	cd web && pnpm build

web-deploy:
	cd web && pnpm build && pnpm dlx wrangler pages deploy dist --project-name fastshared-web

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
