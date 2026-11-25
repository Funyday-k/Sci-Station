GO ?= go

.PHONY: app run headless test
app:
	GO="$(GO)" APP_OUTPUT="$(APP_OUTPUT)" ./packaging/macos/build.sh

run:
	open "$(if $(APP_OUTPUT),$(APP_OUTPUT),Sci-Station.app)"

headless:
	mkdir -p build/bin
	$(GO) build -tags nogui -trimpath -o build/bin/sci-station-server .

test:
	$(GO) test -tags nogui ./...
	node --test tests/*.test.cjs
