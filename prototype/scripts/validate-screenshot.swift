import AppKit
import Foundation

guard CommandLine.arguments.count == 2,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff) else {
    fputs("Cannot read screenshot\n", stderr)
    exit(1)
}

let width = bitmap.pixelsWide
let height = bitmap.pixelsHigh
guard width > height, width >= 700, height >= 300 else {
    fputs("Expected a landscape iPhone screenshot; got \(width)x\(height)\n", stderr)
    exit(1)
}

// The prototype has a bright artwork shape on the left and bright text on the
// right. Check both halves so a blank frame or launch screen fails the job.
var brightLeft = 0
var brightRight = 0
for y in stride(from: height / 8, to: height * 7 / 8, by: 4) {
    for x in stride(from: width / 16, to: width * 15 / 16, by: 4) {
        guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
        let brightness = max(color.redComponent, color.greenComponent, color.blueComponent)
        if brightness > 0.48 {
            if x < width / 2 { brightLeft += 1 } else { brightRight += 1 }
        }
    }
}

print("Screenshot \(width)x\(height): bright samples left=\(brightLeft), right=\(brightRight)")
guard brightLeft >= 100, brightRight >= 30 else {
    fputs("Artwork or track details are missing from the screenshot\n", stderr)
    exit(1)
}
