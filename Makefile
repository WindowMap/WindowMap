.PHONY: build test start stop restart status clean release release-app install uninstall state-to-prod state-to-dev setup-dev

BINARY := .build/debug/WindowMap
DEV_HOME := .dev
LOG := $(DEV_HOME)/windowmap.log
export WINDOWMAP_HOME := $(DEV_HOME)

APP_NAME := WindowMap.app
APP_DIR := .build/release/$(APP_NAME)
RELEASE_BINARY := .build/release/WindowMap
INSTALL_DIR := /Applications
LAUNCH_AGENT := ~/Library/LaunchAgents/org.windowmap.plist
CONFIG_DIR := ~/.config/windowmap

build:
	swift build --product WindowMap

test:
	swift build --product SpreadsheetKitTests && \
		swift build --product WindowMapTests && \
		.build/debug/SpreadsheetKitTests && \
		.build/debug/WindowMapTests

setup-dev:
	mkdir -p $(DEV_HOME)
	test -f $(DEV_HOME)/config.toml || cp Resources/config.toml.example $(DEV_HOME)/config.toml

start: build setup-dev
	pgrep -f '.build/debug/WindowMap$$' > /dev/null && echo "already running" || \
		(nohup $(BINARY) >> $(LOG) 2>&1 & echo "started — tail -f $(LOG)")

stop:
	pkill -f '.build/debug/WindowMap$$' && echo "stopped" || echo "not running"

restart: stop start

status:
	@pgrep -f '.build/debug/WindowMap$$' > /dev/null \
		&& echo "dev:  running (pid $$(pgrep -f '.build/debug/WindowMap$$'))" \
		|| echo "dev:  not running"
	@pgrep -f 'WindowMap.app/Contents/MacOS/WindowMap' > /dev/null \
		&& echo "prod: running (pid $$(pgrep -f 'WindowMap.app/Contents/MacOS/WindowMap'))" \
		|| echo "prod: not running"

clean:
	swift package clean

release:
	swift build -c release --product WindowMap

release-app: release
	rm -rf $(APP_DIR)
	mkdir -p $(APP_DIR)/Contents/MacOS
	mkdir -p $(APP_DIR)/Contents/Resources
	cp $(RELEASE_BINARY) $(APP_DIR)/Contents/MacOS/WindowMap
	cp Resources/Info.plist $(APP_DIR)/Contents/
	cp Resources/config.toml.example $(APP_DIR)/Contents/Resources/
	codesign --force --sign - $(APP_DIR)

install: release-app
	launchctl bootout gui/$$(id -u) $(LAUNCH_AGENT) 2>/dev/null || true
	pkill -f 'WindowMap.app/Contents/MacOS/WindowMap' 2>/dev/null || true
	: > ~/Library/Logs/windowmap.log
	cp -R $(APP_DIR) $(INSTALL_DIR)/
	mkdir -p $(CONFIG_DIR)
	test -f $(CONFIG_DIR)/config.toml || cp Resources/config.toml.example $(CONFIG_DIR)/config.toml
	sed 's|{{HOME}}|$(HOME)|g' Resources/org.windowmap.plist > $(LAUNCH_AGENT)
	launchctl bootstrap gui/$$(id -u) $(LAUNCH_AGENT)
	@echo ""
	@echo "WindowMap installed and started."
	@echo "Config: $(CONFIG_DIR)/config.toml"
	@echo "Logs:   ~/Library/Logs/windowmap.log"
	@echo ""

uninstall:
	launchctl bootout gui/$$(id -u) $(LAUNCH_AGENT) 2>/dev/null || true
	pkill -f 'WindowMap.app/Contents/MacOS/WindowMap' 2>/dev/null || true
	rm -f $(LAUNCH_AGENT)
	rm -rf $(INSTALL_DIR)/$(APP_NAME)

state-to-prod:
	cp $(DEV_HOME)/*.json $(CONFIG_DIR)/

state-to-dev:
	cp $(CONFIG_DIR)/*.json $(DEV_HOME)/
