# dmgbuild settings for Cartridge's installer: the app, a shortcut to Applications and the pixel-art background.
# Used by .github/scripts/make-dmg.sh, which passes the app, background and version with -D. The positions must match
# .github/scripts/make-dmg-background.swift: a 660 x 400 point window, icons centred at (165, 190) and (495, 190).
import os.path

app = defines["app"]
background = defines["background"]

# Finder finds the background through the volume's name. Every installer called just "Cartridge" means that with an
# older one still mounted, the newer window can show the older background - and its version number - so each
# version gets its own name.
volume_name = f"Cartridge {defines['version']}"
format = "ULFO"  # lzfse: smaller than zlib, and every Mac Cartridge runs on can open it
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}
hide_extensions = [os.path.basename(app)]
icon = os.path.join(app, "Contents", "Resources", "Cartridge.icns")

show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
default_view = "icon-view"
# Finder counts the title bar in the window's height, so 28 points more than the 400-point background.
window_rect = ((240, 160), (660, 428))

icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {
    os.path.basename(app): (165, 190),
    "Applications": (495, 190),
}
