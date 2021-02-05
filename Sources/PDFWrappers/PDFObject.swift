import CoreGraphics

public struct PDFObject {
  private let object: CGPDFObjectRef
  public init(object: CGPDFObjectRef) {
    self.object = object
  }

  public var type: CGPDFObjectType { CGPDFObjectGetType(object) }

  public var asBool: Bool? { getAs(.boolean, CGPDFBoolean.self).map { $0 == 1 } }
  public var asInteger: CGPDFInteger? { getAs(.integer, CGPDFInteger.self) }
  public var asReal: CGPDFReal? { getAs(.real, CGPDFReal.self) }
  public var asName: String? { getAs(.name, UnsafePointer<Int8>.self).map(String.init(cString:)) }
  public var asPDFString: PDFString? { getAs(.string, CGPDFStringRef.self).map(PDFString.init) }
  public var asArray: PDFArray? { getAs(.array, CGPDFArrayRef.self).map(PDFArray.init) }
  public var asDictionary: PDFDictionary? { getAs(.dictionary, CGPDFDictionaryRef.self).map(PDFDictionary.init) }
  public var asStream: PDFStream? { getAs(.stream, CGPDFStreamRef.self).map(PDFStream.init) }

  private func getAs<T>(_ objectType: CGPDFObjectType, _ type: T.Type) -> T? {
    var result: T?
    return CGPDFObjectGetValue(object, objectType, &result) ? result : nil
  }

  private func getAs<T: Numeric>(_ objectType: CGPDFObjectType, _ type: T.Type) -> T? {
    var result = T.zero
    return CGPDFObjectGetValue(object, objectType, &result) ? result : nil
  }
}

extension PDFObject: CustomStringConvertible {
  public var description: String {
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
