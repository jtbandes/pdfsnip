# pdfsnip

This Swift package provides two targets:

- `pdfsnip`, a command-line utility to extract images from PDF files.
- `PDFWrappers`, a Swift library wrapping raw pointer-based types from CoreGraphics with a nicer API.

## Usage

### Extract images from a PDF

```sh
$ cd pdfsnip   # directory containing the pdfsnip package and this readme :)
$ swift run pdfsnip [file.pdf] [outdir]
```

Extracts images from the given PDF file and saves them to the output directory.

### Using `PDFWrappers` to traverse PDF data

In your Package.swift, add this package to your package's dependencies, and its `PDFWrappers` product to your target's dependencies. Example:
```swift
let package = Package(
  ...
  dependencies: [
    .package(url: "https://github.com/jtbandes/pdfsnip.git", from: "0.0.1")
  ],
  targets: [
    .target(
      ...
      dependencies: [
        .product(name: "PDFWrappers", package: "pdfsnip"),
      ]),
  ]
)
```

Now you can use `PDFDictionary` and other wrapper types to access PDF data more safely and conveniently:
```swift
let doc: CGPDFDocument = ...
if let rawPageDict = doc.page(at: 1)?.dictionary {
  let pageDict = PDFDictionary(dictionary: rawPageDict)

  // Instead of:
  var str: CGPDFStringRef?
  if CGPDFDictionaryGetString(rawPageDict, "Key", &str) { ... }

  // Use:
  if let str = pageDict[string: "Key"] { ... }
}
```
