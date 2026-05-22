import AppKit
import Testing
@testable import TokMonApp

@MainActor
@Test func menuBarIconIsTemplateImageWithStableSize() {
  let image = TokMonMenuBarIcon.makeImage()

  #expect(image.isTemplate)
  #expect(image.size.width == 18)
  #expect(image.size.height == 18)
}
