import CoreGraphics

public enum Errors: Error {
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
