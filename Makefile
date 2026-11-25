WORKSTATION := RoundtableWorkstation
APP_OUTPUT ?= $(CURDIR)/build/Sci-Station.app
export APP_OUTPUT

.PHONY: app run verify test
app verify:
	@case "$$APP_OUTPUT" in /*) bundle="$$APP_OUTPUT" ;; *) bundle="$$PWD/$$APP_OUTPUT" ;; esac; \
	$(MAKE) -C "$(WORKSTATION)" $@ APP_OUTPUT="$$bundle"

run: app
	/usr/bin/open "$$APP_OUTPUT"

test:
	$(MAKE) -C "$(WORKSTATION)" test
