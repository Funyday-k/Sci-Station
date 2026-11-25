GO ?= go
APP_OUTPUT ?= Sci-Station.app

.PHONY: app verify run headless test
app:
	GO="$(GO)" APP_OUTPUT="$(APP_OUTPUT)" ./packaging/macos/build.sh

verify:
	./packaging/macos/verify.sh "$(APP_OUTPUT)"

run:
	open "$(APP_OUTPUT)"

headless:
	mkdir -p build/bin
	$(GO) build -tags nogui -trimpath -o build/bin/sci-station-server .

test:
	$(GO) test -tags nogui ./...
	node --test tests/*.test.cjs
