import Foundation
import ApplicationServices
import ArgumentParser
import PDFWrappers

extension URL: ExpressibleByArgument {
  public init?(argument: String) {
    self.init(fileURLWithPath: argument)
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

    guard let document = CGPDFDocument(inputFile as CFURL) else {
      throw Errors.couldNotReadPDFDocument
    }

    var totalImages = 0
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
          totalImages += 1
        } catch {
          print("Skipping \(key) on page \(pageIndex): \(error)")
        }
      }
    }

    print("Extracted \(totalImages) images.")
  }
}

PDFSnip.main()
