PAK_NAME := $(shell jq -r .name pak.json)
PAK_TYPE := $(shell jq -r .type pak.json)
PAK_FOLDER := $(shell echo $(PAK_TYPE) | cut -c1)$(shell echo $(PAK_TYPE) | tr '[:upper:]' '[:lower:]' | cut -c2-)s

PUSH_SDCARD_PATH ?= /mnt/SDCARD
PUSH_PLATFORM ?= tg5040

ARCHITECTURES := arm arm64
PLATFORMS := h700 miyoomini my282 my355 rg35xxplus tg5040 tg5050

JQ_VERSION ?= 1.7.1
SYNCTHING_VERSION ?= v2.1.7
# The last release of the Syncthing 1.x line. 1.x keeps its index in LevelDB
# rather than SQLite, which is why it works on the exFAT and FAT32 cards MinUI
# and NextUI require. The 1.x line is closed, so this pin is final, and
# update-syncthing.yaml follows the newest release and deliberately leaves it be.
SYNCTHING_V1_VERSION ?= v1.30.0
MINUI_LIST_VERSION := 0.15.4
MINUI_PRESENTER_VERSION := 0.13.4

SYNCTHING_V1_BINS := $(foreach arch,$(ARCHITECTURES),bin/v1/$(arch)/syncthing)

clean:
	rm -f bin/*/jq || true
	rm -f bin/*/syncthing || true
	rm -rf bin/v1 || true
	rm -f bin/*/minui-list || true
	rm -f bin/*/minui-presenter || true

build: $(foreach platform,$(PLATFORMS),bin/$(platform)/minui-list bin/$(platform)/minui-presenter) $(foreach arch,$(ARCHITECTURES),bin/$(arch)/syncthing bin/$(arch)/jq) $(SYNCTHING_V1_BINS)

bin/arm/jq:
	mkdir -p bin/arm
	curl -f -o bin/arm/jq -sSL https://github.com/jqlang/jq/releases/download/jq-$(JQ_VERSION)/jq-linux-armhf
	curl -f -sSL -o bin/arm/jq.LICENSE "https://raw.githubusercontent.com/jqlang/jq/refs/tags/jq-$(JQ_VERSION)/COPYING"

bin/arm64/jq:
	mkdir -p bin/arm64
	curl -f -o bin/arm64/jq -sSL https://github.com/jqlang/jq/releases/download/jq-$(JQ_VERSION)/jq-linux-arm64
	curl -f -sSL -o bin/arm64/jq.LICENSE "https://raw.githubusercontent.com/jqlang/jq/refs/tags/jq-$(JQ_VERSION)/COPYING"

bin/%/syncthing:
	mkdir -p bin/$*
	curl -sSL https://github.com/syncthing/syncthing/releases/download/$(SYNCTHING_VERSION)/syncthing-linux-$*-$(SYNCTHING_VERSION).tar.gz | tar -xzvf - syncthing-linux-$*-$(SYNCTHING_VERSION)/syncthing && mv syncthing-linux-$*-$(SYNCTHING_VERSION)/syncthing bin/$*/syncthing
	rm -rf syncthing-linux-$*-$(SYNCTHING_VERSION)
	chmod +x bin/$*/syncthing
	curl -f -sSL -o bin/$*/syncthing.LICENSE "https://raw.githubusercontent.com/syncthing/syncthing/refs/tags/$(SYNCTHING_VERSION)/LICENSE"

# A static pattern rule rather than a plain one, because a make stem matches
# across slashes: "bin/%/syncthing" would otherwise claim these targets with $*
# as "v1/arm" and try to fetch a 2.x build for an architecture of that name.
# Naming the targets explicitly gives this rule precedence.
$(SYNCTHING_V1_BINS): bin/v1/%/syncthing:
	mkdir -p bin/v1/$*
	curl -sSL https://github.com/syncthing/syncthing/releases/download/$(SYNCTHING_V1_VERSION)/syncthing-linux-$*-$(SYNCTHING_V1_VERSION).tar.gz | tar -xzvf - syncthing-linux-$*-$(SYNCTHING_V1_VERSION)/syncthing && mv syncthing-linux-$*-$(SYNCTHING_V1_VERSION)/syncthing bin/v1/$*/syncthing
	rm -rf syncthing-linux-$*-$(SYNCTHING_V1_VERSION)
	chmod +x bin/v1/$*/syncthing
	curl -f -sSL -o bin/v1/$*/syncthing.LICENSE "https://raw.githubusercontent.com/syncthing/syncthing/refs/tags/$(SYNCTHING_V1_VERSION)/LICENSE"

bin/h700/minui-list:
	mkdir -p bin/h700
	curl -f -o bin/h700/minui-list -sSL https://github.com/josegonzalez/minui-list/releases/download/$(MINUI_LIST_VERSION)/minui-list-h700-nextui
	chmod +x bin/h700/minui-list

bin/tg5050/minui-list:
	mkdir -p bin/tg5050
	curl -f -o bin/tg5050/minui-list -sSL https://github.com/josegonzalez/minui-list/releases/download/$(MINUI_LIST_VERSION)/minui-list-tg5050-nextui
	chmod +x bin/tg5050/minui-list

bin/h700/minui-presenter:
	mkdir -p bin/h700
	curl -f -o bin/h700/minui-presenter -sSL https://github.com/josegonzalez/minui-presenter/releases/download/$(MINUI_PRESENTER_VERSION)/minui-presenter-h700-nextui
	chmod +x bin/h700/minui-presenter

bin/tg5050/minui-presenter:
	mkdir -p bin/tg5050
	curl -f -o bin/tg5050/minui-presenter -sSL https://github.com/josegonzalez/minui-presenter/releases/download/$(MINUI_PRESENTER_VERSION)/minui-presenter-tg5050-nextui
	chmod +x bin/tg5050/minui-presenter

bin/%/minui-list:
	mkdir -p bin/$*
	curl -f -o bin/$*/minui-list -sSL https://github.com/josegonzalez/minui-list/releases/download/$(MINUI_LIST_VERSION)/minui-list-$*
	chmod +x bin/$*/minui-list

bin/%/minui-presenter:
	mkdir -p bin/$*
	curl -f -o bin/$*/minui-presenter -sSL https://github.com/josegonzalez/minui-presenter/releases/download/$(MINUI_PRESENTER_VERSION)/minui-presenter-$*
	chmod +x bin/$*/minui-presenter

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	$(MAKE) bump-version
	zip -r "dist/$(PAK_NAME).pak.zip" pak.json
	ls -lah dist

bump-version:
	jq '.version = "$(RELEASE_VERSION)"' pak.json > pak.json.tmp
	mv pak.json.tmp pak.json

push: release
	rm -rf "dist/$(PAK_NAME).pak"
	cd dist && unzip "$(PAK_NAME).pak.zip" -d "$(PAK_NAME).pak"
	adb push "dist/$(PAK_NAME).pak/." "$(PUSH_SDCARD_PATH)/$(PAK_FOLDER)/$(PUSH_PLATFORM)/$(PAK_NAME).pak"

test:
	bats tests/

# Print the value of any make variable, e.g. `make print-SYNCTHING_VERSION`.
# update-syncthing.yaml and the bats suite read the pinned version through this.
print-%:
	@echo '$*=$($*)'
