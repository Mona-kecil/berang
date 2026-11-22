import AppKit
import PDFKit
// Makes otters.png, the first page of otters.pdf as a 2× image, under the same license (see pages.tsv).
// usage: swift otters-png.swift otters.pdf otters.png
let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
let page = doc.page(at: 0)!
let box = page.bounds(for: .mediaBox), scale: CGFloat = 2
let ctx = CGContext(data: nil, width: Int(box.width * scale), height: Int(box.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.setFillColor(.white)
ctx.fill(CGRect(x: 0, y: 0, width: box.width * scale, height: box.height * scale))
ctx.scaleBy(x: scale, y: scale)
page.draw(with: .mediaBox, to: ctx)
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
