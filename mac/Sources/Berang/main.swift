import AppKit

let app = NSApplication.shared
let panel = PlayerPanel(player: Player())
panel.orderFrontRegardless()
app.run()
