import AppKit
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    fputs("usage: GenerateIcon.swift <output.png>\n", stderr)
    exit(2)
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let hexPath = root.appendingPathComponent("Macrodroid/Assets/Macrodroid-Official-Icon.png").path

guard let hexImg = NSImage(contentsOfFile: hexPath) else {
    fputs("could not load master asset: \(hexPath)\n", stderr)
    exit(1)
}

guard let tiff = hexImg.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fputs("could not encode icon\n", stderr)
    exit(1)
}

try png.write(to: URL(fileURLWithPath: arguments[1]))
