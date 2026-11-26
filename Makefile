GO ?= go
APP_OUTPUT ?= $(CURDIR)/build/Sci-Station.app
export APP_OUTPUT

.PHONY: app verify run headless test
app:
	GO="$(GO)" ./packaging/macos/build.sh

verify:
	./packaging/macos/verify.sh "$$APP_OUTPUT"

run: app
	/usr/bin/open "$$APP_OUTPUT"

headless:
	mkdir -p build/bin
	$(GO) build -tags nogui -trimpath -o build/bin/sci-station-server .

test:
	$(GO) test -tags nogui ./...
	node --test tests/*.test.cjs
