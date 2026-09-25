import Foundation
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
let handler = VNImageRequestHandler(url: sourceURL, options: [:])
let request = VNGenerateForegroundInstanceMaskRequest()
try handler.perform([request])
guard let result = request.results?.first, !result.allInstances.isEmpty else {
    fatalError("Vision found no foreground instances")
}
let mask = try result.generateScaledMaskForImage(forInstances: result.allInstances, from: handler)
let ci = CIImage(cvPixelBuffer: mask)
let ctx = CIContext(options: [.workingColorSpace: NSNull()])
guard let cg = ctx.createCGImage(ci, from: ci.extent, format: .L8, colorSpace: CGColorSpaceCreateDeviceGray()),
      let dest = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Unable to save mask")
}
CGImageDestinationAddImage(dest, cg, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("Mask write failed") }
print("Vision foreground instances: \(result.allInstances); mask \(cg.width)x\(cg.height)")
