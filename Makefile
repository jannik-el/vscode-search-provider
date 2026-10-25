NAME        := vscode-search-provider
VERSION     := $(shell cat VERSION)
BUS_NAME    := io.github.jannik_el.VSCodeSearchProvider
OBJECT_PATH := /io/github/jannik_el/VSCodeSearchProvider
# code_code.desktop = snap VS Code; use code.desktop for the .deb/apt build.
DESKTOP_ID  := code_code.desktop

SCRIPT := /usr/share/$(NAME)/searchProvider.js
BUILD  := build
STAGE  := $(BUILD)/root
DEB    := $(BUILD)/$(NAME)_$(VERSION)_all.deb

# Files from the pre-packaging install (bus name local.vscode.SearchProvider).
LEGACY_USER := $(HOME)/.local/share/$(NAME) \
               $(HOME)/.local/share/dbus-1/services/local.vscode.SearchProvider.service
LEGACY_SYS  := /usr/local/share/gnome-shell/search-providers/local.vscode.search-provider.ini

SUBST = sed -e 's|@BUS_NAME@|$(BUS_NAME)|g' -e 's|@OBJECT_PATH@|$(OBJECT_PATH)|g' \
            -e 's|@DESKTOP_ID@|$(DESKTOP_ID)|g' -e 's|@SCRIPT@|$(SCRIPT)|g' \
            -e 's|@VERSION@|$(VERSION)|g'

.PHONY: deb install uninstall clean-legacy release run clean

deb: $(DEB)

$(DEB): VERSION src/searchProvider.js data/*.in debian/control.in Makefile
	rm -rf $(STAGE)
	install -Dm644 src/searchProvider.js $(STAGE)$(SCRIPT)
	sed -i 's|^const DESKTOP_ID = .*|const DESKTOP_ID = "$(DESKTOP_ID)";|' $(STAGE)$(SCRIPT)
	install -d $(STAGE)/usr/share/dbus-1/services $(STAGE)/usr/share/gnome-shell/search-providers $(STAGE)/DEBIAN
	$(SUBST) data/$(BUS_NAME).service.in > $(STAGE)/usr/share/dbus-1/services/$(BUS_NAME).service
	$(SUBST) data/$(BUS_NAME).ini.in > $(STAGE)/usr/share/gnome-shell/search-providers/$(BUS_NAME).search-provider.ini
	$(SUBST) debian/control.in > $(STAGE)/DEBIAN/control
	chmod -R u=rwX,go=rX $(STAGE)
	dpkg-deb --root-owner-group --build $(STAGE) $@

# The one sudo step: apt installs the package system-wide.
install: $(DEB)
	sudo apt install -y ./$(DEB)
	$(MAKE) clean-legacy

uninstall:
	sudo apt remove -y $(NAME)

clean-legacy:
	rm -rf $(LEGACY_USER)
	if [ -e $(LEGACY_SYS) ]; then sudo rm -f $(LEGACY_SYS); fi

# Tag the version in VERSION after checking it has a CHANGELOG entry and the
# tree is committed. Push with: git push origin main v$(VERSION)
release:
	grep -q '^## \[$(VERSION)\]' CHANGELOG.md || { echo "CHANGELOG.md has no entry for $(VERSION)"; exit 1; }
	git diff --quiet HEAD || { echo "Commit your changes first"; exit 1; }
	git tag -a v$(VERSION) -m "v$(VERSION)"

# Run from the source tree for testing (stop any installed instance first).
run:
	gjs -m src/searchProvider.js

clean:
	rm -rf $(BUILD)
