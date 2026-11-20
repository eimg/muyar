import AppKit

// Drawn from native shapes; no external image assets or dependencies.
let size = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
NSColor(srgbRed: 0.055, green: 0.052, blue: 0.045, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
let glow = NSGradient(starting: NSColor(srgbRed: 0.28, green: 0.22, blue: 0.10, alpha: 1), ending: NSColor(srgbRed: 0.055, green: 0.052, blue: 0.045, alpha: 1))!
glow.draw(in: NSBezierPath(ovalIn: NSRect(x: -250, y: 200, width: 1250, height: 1250)), relativeCenterPosition: .zero)
let path = NSBezierPath()
path.move(to: NSPoint(x: 205, y: 330))
path.line(to: NSPoint(x: 335, y: 690))
path.line(to: NSPoint(x: 505, y: 440))
path.line(to: NSPoint(x: 675, y: 690))
path.line(to: NSPoint(x: 805, y: 330))
path.lineWidth = 65
path.lineCapStyle = .round
path.lineJoinStyle = .round
NSColor(srgbRed: 0.90, green: 0.76, blue: 0.46, alpha: 1).setStroke()
path.stroke()
NSColor(srgbRed: 0.90, green: 0.76, blue: 0.46, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 474, y: 240, width: 62, height: 62)).fill()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
