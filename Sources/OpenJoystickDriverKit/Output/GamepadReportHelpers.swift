import Foundation

// MARK: - Float clamping

extension Float {
  func clamped(to range: ClosedRange<Float>) -> Float {
    Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
  }
}

// MARK: - Int16 little-endian byte pair

extension Int16 {
  var littleEndianBytes: (UInt8, UInt8) {
    let le = littleEndian
    return (UInt8(le & 0xFF), UInt8((le >> 8) & 0xFF))
  }
}

