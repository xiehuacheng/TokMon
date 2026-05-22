import AppKit

enum TokMonMenuBarIcon {
  @MainActor
  static func makeImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
    let image = NSImage(size: size)
    image.lockFocus()
    defer {
      image.unlockFocus()
      image.isTemplate = true
    }

    NSColor.labelColor.setStroke()
    let transform = NSAffineTransform()
    transform.translateX(by: size.width / 2, yBy: size.height / 2)
    transform.rotate(byDegrees: -90)
    transform.scaleX(by: size.width / 48, yBy: size.height / 48)
    transform.translateX(by: -24, yBy: -24)
    transform.concat()

    strokeLine(from: NSPoint(x: 14, y: 11), to: NSPoint(x: 14, y: 37), width: 3.2)
    strokeLine(from: NSPoint(x: 23, y: 14), to: NSPoint(x: 36, y: 14), width: 4.4)
    strokeLine(from: NSPoint(x: 23, y: 24), to: NSPoint(x: 33, y: 24), width: 4.4)
    strokeLine(from: NSPoint(x: 23, y: 34), to: NSPoint(x: 38, y: 34), width: 4.4)
    strokeCurve(
      from: NSPoint(x: 14, y: 11),
      control1: NSPoint(x: 21, y: 11),
      control2: NSPoint(x: 22, y: 17),
      to: NSPoint(x: 28, y: 17),
      width: 2.4,
      alpha: 0.46,
    )
    strokeCurve(
      from: NSPoint(x: 14, y: 37),
      control1: NSPoint(x: 21, y: 37),
      control2: NSPoint(x: 22, y: 31),
      to: NSPoint(x: 28, y: 31),
      width: 2.4,
      alpha: 0.46,
    )

    return image
  }

  private static func strokeLine(from start: NSPoint, to end: NSPoint, width: CGFloat) {
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineWidth = width
    path.move(to: start)
    path.line(to: end)
    path.stroke()
  }

  private static func strokeCurve(
    from start: NSPoint,
    control1: NSPoint,
    control2: NSPoint,
    to end: NSPoint,
    width: CGFloat,
    alpha: CGFloat,
  ) {
    NSColor.labelColor.withAlphaComponent(alpha).setStroke()
    let path = NSBezierPath()
    path.lineCapStyle = .round
    path.lineWidth = width
    path.move(to: start)
    path.curve(to: end, controlPoint1: control1, controlPoint2: control2)
    path.stroke()
    NSColor.labelColor.setStroke()
  }
}
