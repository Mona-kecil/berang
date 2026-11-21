import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let panel = PlayerPanel(player: Player())
panel.orderFrontRegardless()
app.run()
