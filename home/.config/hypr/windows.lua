-- Hermes Desktop identity. The gateway-window-title plugin sets
-- document.title after the window maps, so workspace stickiness is handled
-- by ~/.local/bin/zet-hermes-gateway-windows rather than a workspace= rule.
o.window({ class = "^Hermes$", title = "^Hermes · Veelox$" }, { tag = "+hermes-veelox" })
o.window({ class = "^Hermes$", title = "^Hermes · Halla$" }, { tag = "+hermes-halla" })

-- Super+Ctrl+X: X compose webapp, sized like the in-app modal.
o.window("brave-x.com__compose_post-Default", { float = true })
o.window("brave-x.com__compose_post-Default", { center = true })
o.window("brave-x.com__compose_post-Default", { size = { 600, 640 } })

-- Ibara operator console floats; other Quickshell windows keep their own rules.
o.window({ class = "^org.quickshell$", title = "^ibara · console$" }, { float = true, center = true })
