import AppKit
import CoreText
// Makes otters.pdf. usage: swift otters-pdf.swift otters.pdf
// Three pages of set lines: a running header, centered page numbers, a heading, a word hyphenated at a line end,
// a paragraph that runs on to the next page, and a References section.
let url = URL(fileURLWithPath: CommandLine.arguments[1])
var box = CGRect(x: 0, y: 0, width: 612, height: 792)
let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
let body = NSFont(name: "Georgia", size: 12)!, small = NSFont(name: "Helvetica", size: 9)!, head = NSFont(name: "Georgia-Bold", size: 16)!
func line(_ s: String, _ font: NSFont, x: CGFloat, y: CGFloat) {
    ctx.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: [.font: font])), ctx)
}
func paragraph(_ lines: [String], y: inout CGFloat) {
    for l in lines { line(l, body, x: 72, y: y); y -= 16 }
    y -= 12
}
let pages: [[[String]]] = [
    [["#Life in the Water"],
     ["Otters are distinguished by their long, slim bodies, powerful webbed feet",
      "for swimming, and their dense fur, which keeps them warm and buoyant."],
     ["Some species are adapted to cold waters and need a high metab-",
      "olic rate to stay warm. They eat fish, frogs, birds, and shellfish,",
      "depending on where they live and what the season"]],
    [["brings. Young otters stay with their family for about a year.",
      "They can live up to sixteen years in the wild."],
     ["#How Otters Hunt"],
     ["Otters find prey with their whiskers, which sense movement in murky",
      "water. Sea otters use stones as tools to open shells."]],
    [["People hunted otters for their pelts for centuries, and some species",
      "are still endangered today."],
     ["#References"],
     ["Kruuk, H. Otters: Ecology, Behaviour and Conservation. 2006."]],
]
for (i, paragraphs) in pages.enumerated() {
    ctx.beginPDFPage(nil)
    line("Field Notes on Otters", small, x: 72, y: 750)
    var y: CGFloat = 700
    for p in paragraphs {
        if p[0].hasPrefix("#") { line(String(p[0].dropFirst()), head, x: 72, y: y); y -= 30 } else { paragraph(p, y: &y) }
    }
    line("\(i + 1)", small, x: 303, y: 40)
    ctx.endPDFPage()
}
ctx.closePDF()
