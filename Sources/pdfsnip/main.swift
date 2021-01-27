import Foundation
import ApplicationServices
import ArgumentParser

extension URL: ExpressibleByArgument {
  public init?(argument: String) {
    self.init(fileURLWithPath: argument)
  }
}

enum Errors: Error {
  case couldNotReadPDFDocument
  case couldNotReadPDFPage
  case couldNotReadImageProperties
  case unknownColorSpace(String)
  case invalidColorSpace(String)
  case invalidNumber
  case unsupportedStreamFormat(CGPDFDataFormat)
  case couldNotInitializeImage
  case couldNotWriteImage
}

extension CGColorSpace {
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

struct PDFStream {
  let stream: CGPDFStreamRef
  
  var dictionary: PDFDictionary? { CGPDFStreamGetDictionary(stream).map(PDFDictionary.init) }
  var dataAndFormat: (data: Data, format: CGPDFDataFormat)? {
    var format: CGPDFDataFormat = .raw
    return CGPDFStreamCopyData(stream, &format).map { ($0 as Data, format) }
  }
}

struct PDFString: CustomStringConvertible {
  let string: CGPDFStringRef
  
  var asData: Data? { CGPDFStringGetBytePtr(string).map { Data(bytes: $0, count: CGPDFStringGetLength(string)) } }
  var asString: String? { CGPDFStringCopyTextString(string) as String? }
  
  var description: String {
    asString?.debugDescription ?? asData?.debugDescription ?? "<invalid string>"
  }
}

struct PDFObject {
  let object: CGPDFObjectRef
  var type: CGPDFObjectType { CGPDFObjectGetType(object) }
  
  var asStream: PDFStream? { getAs(.stream, CGPDFStreamRef.self).map(PDFStream.init) }
  var asPDFString: PDFString? { getAs(.string, CGPDFStringRef.self).map(PDFString.init) }
  var asName: String? { getAs(.name, UnsafePointer<Int8>.self).map(String.init(cString:)) }
  var asDictionary: PDFDictionary? { getAs(.dictionary, CGPDFDictionaryRef.self).map(PDFDictionary.init) }
  var asInteger: CGPDFInteger? { getAs(.integer, CGPDFInteger.self) }
  var asBool: Bool? { getAs(.boolean, CGPDFBoolean.self).map { $0 == 1 } }
  var asArray: PDFArray? { getAs(.array, CGPDFArrayRef.self).map(PDFArray.init) }
  var asReal: CGPDFReal? { getAs(.real, CGPDFReal.self) ?? asInteger.map(CGPDFReal.init) }
  
  func asRealThrowing() throws -> CGPDFReal {
    if let real = asReal { return real }
    throw Errors.invalidNumber
  }
  
  func asColorSpace(bitsPerComponent: Int) throws -> (colorSpace: CGColorSpace, defaultDecode: [CGPDFReal])? {
    try CGColorSpace.fromPDF(self, bitsPerComponent: bitsPerComponent)
  }
  
  private func getAs<T>(_ objectType: CGPDFObjectType, _ type: T.Type) -> T? {
    var result: T?
    return CGPDFObjectGetValue(object, objectType, &result) ? result : nil
  }
}

extension PDFObject: CustomStringConvertible {
  var description: String {
    switch type {
    case .null: return "<null>"
    case .boolean: return asBool!.description
    case .integer: return asInteger!.description
    case .real: return asReal!.description
    case .name: return asName!.debugDescription
    case .string: return asPDFString!.description
    case .array: return asArray!.description
    case .dictionary: return asDictionary!.description
    case .stream: return "\(asStream!)"
    default:
      return "<unknown object type \(type)>"
    }
  }
}

struct PDFArray: RandomAccessCollection, CustomStringConvertible {
  let array: CGPDFArrayRef
  
  var startIndex: Int { 0 }
  var endIndex: Int { count }
  var count: Int { CGPDFArrayGetCount(array) }
  
  subscript(_ index: Int) -> PDFObject? {
    precondition(0 <= index && index < count)
    var result: CGPDFObjectRef?
    return CGPDFArrayGetObject(array, index, &result) ? result.map(PDFObject.init) : nil
  }
  
  subscript(stream index: Int) -> PDFStream? { self[index]?.asStream }
  subscript(dictionary index: Int) -> PDFDictionary? { self[index]?.asDictionary }
  subscript(array index: Int) -> PDFArray? { self[index]?.asArray }
  subscript(name index: Int) -> String? { self[index]?.asName }
  subscript(integer index: Int) -> CGPDFInteger? { self[index]?.asInteger }
  subscript(real index: Int) -> CGPDFReal? { self[index]?.asReal }
  subscript(bool index: Int) -> Bool? { self[index]?.asBool }
  
  func asRealArray(requiredCount expectedCount: Int) throws -> [CGPDFReal]? {
    if count != expectedCount {
      throw Errors.invalidNumber
    }
    return try? map {
      if let real = $0?.asReal { return real }
      throw Errors.invalidNumber
    }
  }
  
  var description: String {
    map { $0.debugDescription }.joined(separator: ", ")
  }
}

struct PDFDictionary: CustomStringConvertible {
  let dictionary: CGPDFDictionaryRef
  
  subscript(_ key: String) -> PDFObject? {
    var result: CGPDFObjectRef?
    return CGPDFDictionaryGetObject(dictionary, key, &result) ? result.map(PDFObject.init) : nil
  }
  
  subscript(stream key: String) -> PDFStream? { self[key]?.asStream }
  subscript(dictionary key: String) -> PDFDictionary? { self[key]?.asDictionary }
  subscript(array key: String) -> PDFArray? { self[key]?.asArray }
  subscript(name key: String) -> String? { self[key]?.asName }
  subscript(integer key: String) -> CGPDFInteger? { self[key]?.asInteger }
  subscript(real key: String) -> CGPDFReal? { self[key]?.asReal }
  subscript(bool key: String) -> Bool? { self[key]?.asBool }
  
  func forEach(_ body: (_ key: String, _ value: PDFObject) -> Void) {
    withoutActuallyEscaping(body) { body in
      withExtendedLifetime(body as AnyObject) { body in
        CGPDFDictionaryApplyFunction(dictionary, { (key, value, info) in
          let body = Unmanaged<AnyObject>.fromOpaque(info!).takeUnretainedValue() as! (String, PDFObject) -> Void
          body(String(cString: key), PDFObject(object: value))
        }, Unmanaged.passUnretained(body).toOpaque())
      }
    }
  }
  
  var description: String {
    var result: [String] = []
    forEach { key, value in
      result.append("\(key.debugDescription): \(value)")
    }
    return "[\(result.joined(separator: ", "))]"
  }
}

extension PDFObject {
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
        bytesPerRow: (bitsPerComponent * colorSpace.numberOfComponents * width) / 8,
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

struct PDFSnip: ParsableCommand {
  @Argument(help: "Input PDF file")
  var inputFile: URL
  
  @Argument(help: "Directory to output images")
  var outputDirectory: URL
  
  func validate() throws {
    guard try inputFile.checkResourceIsReachable() else {
      throw URLError(.fileDoesNotExist)
    }
    guard try inputFile.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == false else {
      throw URLError(.fileIsDirectory)
    }
  }
  
  func run() throws {
    try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    
    guard let document = CGPDFDocument(inputFile as CFURL) else { throw Errors.couldNotReadPDFDocument }
    for pageIndex in 1...document.numberOfPages {
      guard let pageDict = document.page(at: pageIndex)?.dictionary.map(PDFDictionary.init) else {
        throw Errors.couldNotReadPDFPage
      }
      
      pageDict[dictionary: "Resources"]?[dictionary: "XObject"]?.forEach { key, value in
        do {
          let image = try value.asImage()
          let utType = image.utType ?? kUTTypeJPEG
          let ext = UTTypeCopyPreferredTagWithClass(utType, kUTTagClassFilenameExtension)?.takeRetainedValue() as String?
          let outputURL = outputDirectory.appendingPathComponent("page\(pageIndex)-\(key).\(ext ?? "jpg")")
          guard
            let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, utType, 1, nil),
            case _ = CGImageDestinationAddImage(dest, image, nil),
            CGImageDestinationFinalize(dest)
          else {
            throw Errors.couldNotWriteImage
          }
          print("Wrote to \(outputURL.path)")
        } catch {
          print("Skipping XObject \(key): \(error)")
        }
      }
    }
  }
}

PDFSnip.main()
