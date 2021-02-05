import CoreGraphics

extension SignedInteger {
  func dividedRoundingUp(by divisor: Self) -> Self {
    (self - 1) / divisor + 1
  }
}

public extension PDFObject {
  func asImage() throws -> CGImage {
    guard let stream = self.asStream,
          let dataAndFormat = stream.dataAndFormat,
          let dict = stream.dictionary,
          dict[name: "Subtype"] == "Image",
          let width = dict[integer: "Width"],
          let height = dict[integer: "Height"],
          let bitsPerComponent = dict[integer: "BitsPerComponent"],
          let (colorSpace, defaultDecode) = try dict["ColorSpace"]?.asColorSpace(bitsPerComponent: bitsPerComponent)
    else {
      throw Errors.couldNotReadImageProperties
    }

    let decode = try dict[array: "Decode"]?.asRealArray(requiredCount: 2 * colorSpace.numberOfComponents) ?? defaultDecode

    let shouldInterpolate = dict[bool: "Interpolate"] ?? false

    let intent: CGColorRenderingIntent
    switch dict[name: "Intent"] {
    case "AbsoluteColorimetric": intent = .absoluteColorimetric
    case "RelativeColorimetric": intent = .relativeColorimetric
    case "Saturation": intent = .saturation
    case "Perceptual": intent = .perceptual
    default: intent = .defaultIntent
    }

    let image: CGImage?
    switch dataAndFormat {
    case let (data, .raw):
      image = CGImage(
        width: width,
        height: height,
        bitsPerComponent: bitsPerComponent,
        bitsPerPixel: bitsPerComponent * colorSpace.numberOfComponents,
        bytesPerRow: (bitsPerComponent * colorSpace.numberOfComponents * width).dividedRoundingUp(by: 8),
        space: colorSpace,
        bitmapInfo: CGBitmapInfo(),
        provider: CGDataProvider(data: data as CFData)!,
        decode: decode,
        shouldInterpolate: shouldInterpolate,
        intent: intent)

    case let (data, .jpegEncoded), let (data, .JPEG2000):
      image = CGImage(
        jpegDataProviderSource: CGDataProvider(data: data as CFData)!,
        decode: decode,
        shouldInterpolate: shouldInterpolate,
        intent: intent)

    case let (_, format):
      throw Errors.unsupportedStreamFormat(format)
    }

    if let image = image {
      return image
    }
    throw Errors.couldNotInitializeImage
  }
}
