WORKSTATION := RoundtableWorkstation
APP_OUTPUT ?= $(CURDIR)/build/Sci-Station.app

.PHONY: app run verify test
app verify:
	$(MAKE) -C "$(WORKSTATION)" $@ APP_OUTPUT="$(APP_OUTPUT)"

run: app
	/usr/bin/open "$(APP_OUTPUT)"

test:
	$(MAKE) -C "$(WORKSTATION)" test
