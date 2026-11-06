APP_NAME = FilmDown
APP_BUNDLE = $(APP_NAME).app
MACOS_DIR = $(APP_BUNDLE)/Contents/MacOS
RESOURCES_DIR = $(APP_BUNDLE)/Contents/Resources

all: build

build:
	@echo "Building native FilmDown Liquid Glass macOS App..."
	@mkdir -p $(MACOS_DIR) $(RESOURCES_DIR)
	@cp -f Info.plist $(APP_BUNDLE)/Contents/Info.plist 2>/dev/null || true
	@cp -f AppIcon.icns $(RESOURCES_DIR)/AppIcon.icns 2>/dev/null || true
	@cp -f src/engine.py $(RESOURCES_DIR)/engine.py
	@swiftc -O -parse-as-library src/FilmDownApp.swift -o $(MACOS_DIR)/$(APP_NAME)
	@codesign --force --deep --sign - $(APP_BUNDLE)
	@echo "Build successful: $(APP_BUNDLE)"

install: build
	@echo "Installing to ~/Desktop/ALPTUĞ İÇERİK/..."
	@rm -rf "$$HOME/Desktop/ALPTUĞ İÇERİK/$(APP_BUNDLE)"
	@cp -R $(APP_BUNDLE) "$$HOME/Desktop/ALPTUĞ İÇERİK/"
	@echo "Installed successfully."

clean:
	@rm -rf $(APP_BUNDLE)
