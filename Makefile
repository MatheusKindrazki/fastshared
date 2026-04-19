.PHONY: bootstrap ios backend-dev backend-test db-migrate db-generate lint fmt clean web-dev web-build web-deploy testflight testflight-doctor testflight-bootstrap

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
	@command -v bundle >/dev/null 2>&1 || gem install bundler --user-install
	cd apple && bundle config set --local path "vendor/bundle" && bundle install

testflight-doctor:
	cd apple && set -a && . ./.env.testflight && set +a && bundle exec fastlane ios doctor

testflight:
	cd apple && set -a && . ./.env.testflight && set +a && bundle exec fastlane ios beta
