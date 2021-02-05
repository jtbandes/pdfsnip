import CoreGraphics
import Foundation

public struct PDFString {
  private let string: CGPDFStringRef
  public init(string: CGPDFStringRef) {
    self.string = string
  }

  public var asData: Data? { CGPDFStringGetBytePtr(string).map { Data(bytes: $0, count: CGPDFStringGetLength(string)) } }
  public var asString: String? { CGPDFStringCopyTextString(string) as String? }
}

extension PDFString: CustomStringConvertible {
  public var description: String {
    asString?.debugDescription ?? asData?.debugDescription ?? "<invalid string>"
  }
}
