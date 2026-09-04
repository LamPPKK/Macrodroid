import AppKit
import Foundation

let arguments = CommandLine.arguments
 guard arguments.count == 2 else {
    fputs("usage: GenerateIcon.swift <output.png>\n", stderr)
    exit(2)
}

let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()

let background = NSGradient(colors: [
    NSColor(calibratedRed: 0.035, green: 0.19, blue: 0.24, alpha: 1),
    NSColor(calibratedRed: 0.008, green: 0.035, blue: 0.055, alpha: 1)
])!
let rect = NSRect(origin: .zero, size: size)
let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: 40, dy: 40), xRadius: 220, yRadius: 220)
background.draw(in: rounded, angle: -55)

NSColor(calibratedRed: 0.25, green: 0.74, blue: 0.82, alpha: 0.55).setStroke()
rounded.lineWidth = 20
rounded.stroke()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont(name: "Times New Roman Bold", size: 650) ?? NSFont.systemFont(ofSize: 650, weight: .black),
    .foregroundColor: NSColor(calibratedRed: 0.91, green: 0.68, blue: 0.22, alpha: 1),
    .paragraphStyle: paragraph,
    .shadow: shadow
]
NSString(string: "T").draw(in: NSRect(x: 80, y: 165, width: 864, height: 700), withAttributes: attributes)

let badgeAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 92, weight: .black),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph
]
NSString(string: "TFTMAC").draw(in: NSRect(x: 100, y: 80, width: 824, height: 120), withAttributes: badgeAttributes)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("could not encode icon\n", stderr)
    exit(1)
}
try png.write(to: URL(fileURLWithPath: arguments[1]))
