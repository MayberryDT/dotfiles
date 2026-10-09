-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- hyprpm remembers enabled plugins but Hyprland does not load them by itself
-- after a new compositor session. Reload the enabled set once IPC is ready.
o.launch_on_start("/home/tyler/.local/bin/zet-hyprminimize-load")
o.launch_on_start("/home/tyler/.local/bin/zet-pointer-capture-load")

-- Keep copied content available after its source application closes.
o.launch_on_start("wl-clip-persist --clipboard regular")
