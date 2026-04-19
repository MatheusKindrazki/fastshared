.PHONY: bootstrap ios backend-dev backend-test db-migrate db-generate lint fmt clean

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
