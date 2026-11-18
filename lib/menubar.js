// MacGlass — macOS-style menu bar (Plasma scripting API, run via evaluateScript).
// Removes every existing panel (the Krema dock replaces the task bar) and builds:
//   AppGrid · active app · Global Menu · ⟷ · tray · Control Center · Clock/Notification Center
// Widget settings are written afterwards by configure-menubar.py (needs plasmashell stopped).

var old = panels();
for (var i = 0; i < old.length; i++) {
    old[i].remove();
}

var bar = new Panel("org.kde.panel");
bar.location = "top";
bar.screen = 0;            // primary screen
bar.lengthMode = "fill";
bar.floating = false;
bar.hiding = "none";
bar.height = 32;

bar.addWidget("dev.xarbit.appgrid");
bar.addWidget("org.macglass.activeapp");
bar.addWidget("org.kde.plasma.appmenu");
bar.addWidget("org.kde.plasma.panelspacer");
bar.addWidget("org.kde.plasma.systemtray");
bar.addWidget("KdeControlStation");
bar.addWidget("org.macglass.notificationcenter");

print("MACGLASS_PANEL " + bar.id);
