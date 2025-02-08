TAG ?= latest
PAK_NAME := $(shell jq -r .label config.json)

PLATFORMS := tg5040 rg35xxplus
MINUI_LIST_VERSION := 0.3.1
MINUI_KEYBOARD_VERSION := 0.2.1

clean:
	rm -f bin/syncthing-arm || true
	rm -f bin/syncthing-arm64 || true
	rm -f bin/sdl2imgshow || true
	rm -f bin/minui-keyboard-* || true
	rm -f bin/minui-list-* || true
	rm -f res/fonts/BPreplayBold.otf || true

build: $(foreach platform,$(PLATFORMS),bin/minui-keyboard-$(platform) bin/minui-list-$(platform)) bin/sdl2imgshow bin/syncthing-arm bin/syncthing-arm64 res/fonts/BPreplayBold.otf

bin/syncthing-arm:
	curl -sSL https://github.com/syncthing/syncthing/releases/download/v1.29.2/syncthing-linux-arm-v1.29.2.tar.gz | tar -xzvf - syncthing-linux-arm-v1.29.2/syncthing && mv syncthing-linux-arm-v1.29.2/syncthing bin/syncthing-arm
	rm -rf syncthing-linux-arm-v1.29.2

bin/syncthing-arm64:
	curl -sSL https://github.com/syncthing/syncthing/releases/download/v1.29.2/syncthing-linux-arm64-v1.29.2.tar.gz | tar -xzvf - syncthing-linux-arm64-v1.29.2/syncthing && mv syncthing-linux-arm64-v1.29.2/syncthing bin/syncthing-arm64
	rm -rf syncthing-linux-arm64-v1.29.2

# dynamically create the minui-keyboard target for all platforms
bin/minui-keyboard-%:
	curl -f -o bin/minui-keyboard-$* -sSL https://github.com/josegonzalez/minui-keyboard/releases/download/$(MINUI_KEYBOARD_VERSION)/minui-keyboard-$*
	chmod +x bin/minui-keyboard-$*

bin/minui-list-%:
	curl -f -o bin/minui-list-$* -sSL https://github.com/josegonzalez/minui-list/releases/download/$(MINUI_LIST_VERSION)/minui-list-$*
	chmod +x bin/minui-list-$*

bin/sdl2imgshow:
	docker buildx build --platform linux/arm64 --load -f Dockerfile.sdl2imgshow --progress plain -t app/sdl2imgshow:$(TAG) .
	docker container create --name extract app/sdl2imgshow:$(TAG)
	docker container cp extract:/go/src/github.com/kloptops/sdl2imgshow/build/sdl2imgshow bin/sdl2imgshow
	docker container rm extract
	chmod +x bin/sdl2imgshow

res/fonts/BPreplayBold.otf:
	mkdir -p res/fonts
	curl -sSL -o res/fonts/BPreplayBold.otf "https://raw.githubusercontent.com/shauninman/MinUI/refs/heads/main/skeleton/SYSTEM/res/BPreplayBold-unhinted.otf"

release: build
	mkdir -p dist
	git archive --format=zip --output "dist/$(PAK_NAME).pak.zip" HEAD
	while IFS= read -r file; do zip -r "dist/$(PAK_NAME).pak.zip" "$$file"; done < .gitarchiveinclude
	ls -lah dist
