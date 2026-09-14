-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- hyprpm remembers enabled plugins but Hyprland does not load them by itself
-- after a new compositor session. Reload the enabled set once IPC is ready.
o.launch_on_start("/home/tyler/.local/bin/zet-hyprminimize-load")
o.launch_on_start("/home/tyler/.local/bin/zet-pointer-capture-load")
o.launch_on_start("/home/tyler/.local/bin/zet-hdmi-x-ensure")
