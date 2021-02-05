import CoreGraphics

public struct PDFArray: RandomAccessCollection {
  private let array: CGPDFArrayRef
  public init(array: CGPDFArrayRef) {
    self.array = array
  }

  public var startIndex: Int { 0 }
  public var endIndex: Int { count }
  public var count: Int { CGPDFArrayGetCount(array) }

  // It's not clear from the CGPDF documentation why this can return nil, but it apparently sometimes can.
  public subscript(_ index: Int) -> PDFObject? {
    precondition(0 <= index && index < count)
    var result: CGPDFObjectRef?
    return CGPDFArrayGetObject(array, index, &result) ? result.map(PDFObject.init) : nil
  }

  public subscript(bool index: Int) -> Bool? { self[index]?.asBool }
  public subscript(integer index: Int) -> CGPDFInteger? { self[index]?.asInteger }
  public subscript(real index: Int) -> CGPDFReal? { self[index]?.asReal }
  public subscript(name index: Int) -> String? { self[index]?.asName }
  public subscript(string index: Int) -> PDFString? { self[index]?.asPDFString }
  public subscript(array index: Int) -> PDFArray? { self[index]?.asArray }
  public subscript(dictionary index: Int) -> PDFDictionary? { self[index]?.asDictionary }
  public subscript(stream index: Int) -> PDFStream? { self[index]?.asStream }
}

extension PDFArray: CustomStringConvertible {
  public var description: String {
    "[\(map { $0?.description ?? "(unknown object)" }.joined(separator: ", "))]"
  }
}

extension PDFArray {
  /// Utility for easily casting an array that contains only numbers.
  func asRealArray(requiredCount expectedCount: Int) throws -> [CGPDFReal]? {
    if count != expectedCount {
      throw Errors.invalidNumber
    }
    return try? map {
      if let real = $0?.asReal { return real }
      throw Errors.invalidNumber
    }
  }
}
