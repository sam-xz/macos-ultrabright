import os

build_dir = os.path.abspath(defines["build_dir"])
app_name = "MacOS Ultrabright.app"
app_path = os.path.join(build_dir, app_name)

format = "UDZO"
filesystem = "HFS+"
files = [app_path, (os.path.join(build_dir, "INSTALL.txt"), ".INSTALL.txt")]
symlinks = {"Applications": "/Applications"}
icon = os.path.join(app_path, "Contents", "Resources", "AppIcon.icns")
background = os.path.join(build_dir, "Installer.tiff")

window_rect = ((200, 160), (640, 432))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
show_icon_preview = False
show_item_info = False
include_icon_view_settings = True
include_list_view_settings = False
arrange_by = None
grid_spacing = 99
label_pos = "bottom"
text_size = 13
icon_size = 112
icon_locations = {app_name: (164, 220), "Applications": (476, 220)}
