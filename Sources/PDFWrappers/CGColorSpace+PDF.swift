import CoreGraphics
import Foundation

public extension PDFObject {
  func asColorSpace(bitsPerComponent: Int) throws -> (colorSpace: CGColorSpace, defaultDecode: [CGPDFReal])? {
    try CGColorSpace.fromPDF(self, bitsPerComponent: bitsPerComponent)
  }
}

public extension CGColorSpace {
  static func fromPDF(_ object: PDFObject, bitsPerComponent: Int) throws -> (colorSpace: CGColorSpace, defaultDecode: [CGPDFReal])? {
    switch object.asName {
    case "DeviceGray": return (CGColorSpaceCreateDeviceGray(), [0, 1])
    case "DeviceRGB": return (CGColorSpaceCreateDeviceRGB(), [0, 1, 0, 1, 0, 1])
    case "DeviceCMYK": return (CGColorSpaceCreateDeviceCMYK(), [0, 1, 0, 1, 0, 1, 0, 1])
    case let name?: throw Errors.unknownColorSpace(name)
    default: break
    }

    guard let array = object.asArray else {
      return nil
    }

    switch array[name: 0] {
    case "CalGray":
      guard let params = array[dictionary: 1] else {
        throw Errors.invalidColorSpace("missing CalGray parameters")
      }
      guard let whitePoint = try params[array: "WhitePoint"]?.asRealArray(requiredCount: 3) else {
        throw Errors.invalidColorSpace("missing WhitePoint for CalGray")
      }
      return CGColorSpace(
        calibratedGrayWhitePoint: whitePoint,
        blackPoint: try params[array: "BlackPoint"]?.asRealArray(requiredCount: 3),
        gamma: params[real: "Gamma"] ?? 1)
        .map { ($0, [0, 1]) }

    case "CalRGB":
      guard let params = array[dictionary: 1] else {
        throw Errors.invalidColorSpace("missing CalRGB parameters")
      }
      guard let whitePoint = try params[array: "WhitePoint"]?.asRealArray(requiredCount: 3) else {
        throw Errors.invalidColorSpace("missing WhitePoint for CalRGB")
      }
      return CGColorSpace(
        calibratedRGBWhitePoint: whitePoint,
        blackPoint: try params[array: "BlackPoint"]?.asRealArray(requiredCount: 3),
        gamma: try params[array: "Gamma"]?.asRealArray(requiredCount: 3),
        matrix: try params[array: "Matrix"]?.asRealArray(requiredCount: 9))
        .map { ($0, [0, 1, 0, 1, 0, 1]) }

    case "Lab":
      guard let params = array[dictionary: 1] else {
        throw Errors.invalidColorSpace("missing Lab parameters")
      }
      guard let whitePoint = try params[array: "WhitePoint"]?.asRealArray(requiredCount: 3) else {
        throw Errors.invalidColorSpace("missing WhitePoint for Lab")
      }
      guard let range = try params[array: "Range"]?.asRealArray(requiredCount: 4) else {
        throw Errors.invalidColorSpace("missing Range for Lab")
      }
      return CGColorSpace(
        labWhitePoint: whitePoint,
        blackPoint: try params[array: "BlackPoint"]?.asRealArray(requiredCount: 3),
        range: range)
        .map { ($0, [0, 100] + range) }

    case "ICCBased":
      guard let stream = array[stream: 1] else {
        throw Errors.invalidColorSpace("missing ICCBased stream")
      }
      guard let params = stream.dictionary else {
        throw Errors.invalidColorSpace("missing ICCBased parameters")
      }
      guard let nComponents = params[integer: "N"], nComponents == 1 || nComponents == 3 || nComponents == 4 else {
        throw Errors.invalidColorSpace("invalid num components for ICCBased")
      }
      guard let range = try params[array: "Range"]?.asRealArray(requiredCount: 2 * nComponents) else {
        throw Errors.invalidColorSpace("missing Range for ICCBased")
      }
      return CGColorSpace(
        iccBasedNComponents: nComponents,
        range: range,
        profile: CGDataProvider(data: (stream.dataAndFormat?.data ?? Data()) as CFData)!,
        alternate: try params["Alternate"]?.asColorSpace(bitsPerComponent: bitsPerComponent)?.colorSpace)
        .map { ($0, range) }

    case "Indexed":
      guard let base = try array[1]?.asColorSpace(bitsPerComponent: bitsPerComponent)?.colorSpace else {
        throw Errors.invalidColorSpace("missing base for Indexed")
      }
      guard let lastIndex = array[integer: 2] else {
        throw Errors.invalidColorSpace("missing last for Indexed")
      }
      guard let lookup = array[3] else {
        throw Errors.invalidColorSpace("missing lookup for Indexed")
      }
      guard let colorTable = lookup.asStream?.dataAndFormat?.data ?? lookup.asPDFString?.asData else {
        throw Errors.invalidColorSpace("invalid colorTable for Indexed")
      }
      let expectedSize = base.numberOfComponents * (lastIndex + 1)
      guard colorTable.count == expectedSize else {
        throw Errors.invalidColorSpace("invalid colorTable size \(colorTable.count) for Indexed, expected \(expectedSize)")
      }
      return colorTable.withUnsafeBytes {
        CGColorSpace(indexedBaseSpace: base, last: lastIndex, colorTable: $0.bindMemory(to: UInt8.self).baseAddress!)
          .map { ($0, [0, CGPDFReal(1 << bitsPerComponent - 1)]) }
      }

    case let name?: throw Errors.unknownColorSpace(name)
    default: throw Errors.unknownColorSpace("unexpected type \(object.type.rawValue)")
    }
  }
}
