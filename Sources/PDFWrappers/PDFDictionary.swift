import CoreGraphics

public struct PDFDictionary {
  private let dictionary: CGPDFDictionaryRef
  public init(dictionary: CGPDFDictionaryRef) {
    self.dictionary = dictionary
  }

  public subscript(_ key: String) -> PDFObject? {
    var result: CGPDFObjectRef?
    return CGPDFDictionaryGetObject(dictionary, key, &result) ? result.map(PDFObject.init) : nil
  }

  public subscript(stream key: String) -> PDFStream? { self[key]?.asStream }
  public subscript(dictionary key: String) -> PDFDictionary? { self[key]?.asDictionary }
  public subscript(array key: String) -> PDFArray? { self[key]?.asArray }
  public subscript(name key: String) -> String? { self[key]?.asName }
  public subscript(string key: String) -> PDFString? { self[key]?.asPDFString }
  public subscript(integer key: String) -> CGPDFInteger? { self[key]?.asInteger }
  public subscript(real key: String) -> CGPDFReal? { self[key]?.asReal }
  public subscript(bool key: String) -> Bool? { self[key]?.asBool }

  public func forEach(_ body: (_ key: String, _ value: PDFObject) -> Void) {
    withoutActuallyEscaping(body) { body in
      withExtendedLifetime(body as AnyObject) { body in
        CGPDFDictionaryApplyFunction(dictionary, { (key, value, info) in
          let body = Unmanaged<AnyObject>.fromOpaque(info!).takeUnretainedValue() as! (String, PDFObject) -> Void
          body(String(cString: key), PDFObject(object: value))
        }, Unmanaged.passUnretained(body).toOpaque())
      }
    }
  }
}

extension PDFDictionary: CustomStringConvertible {
  public var description: String {
    var result: [String] = []
    forEach { key, value in
      result.append("\(key.debugDescription): \(value)")
    }
    return "[\(result.joined(separator: ", "))]"
  }
}
