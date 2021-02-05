import CoreGraphics
import Foundation

public struct PDFStream {
  private let stream: CGPDFStreamRef
  public init(stream: CGPDFStreamRef) {
    self.stream = stream
  }

  public var dictionary: PDFDictionary? { CGPDFStreamGetDictionary(stream).map(PDFDictionary.init) }
  public var dataAndFormat: (data: Data, format: CGPDFDataFormat)? {
    var format: CGPDFDataFormat = .raw
    return CGPDFStreamCopyData(stream, &format).map { ($0 as Data, format) }
  }
}
