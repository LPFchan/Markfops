import AppKit

let sampleSource = """
# Hello world
`nice` work on this `markdown`
"""

let textWidth: CGFloat = 640

/// Headless mode: how expensive is reading back every character position from TextKit?
func runBench(iterations: Int) {
    let chars = parseSource(sampleSource)
    let presentations = [("source", sourcePresentation(chars)), ("rendered", renderedPresentation(chars))]
    print("characters: \(chars.count), width: \(Int(textWidth)) pt, iterations: \(iterations)")
    for (name, presentation) in presentations {
        var samples: [Double] = []
        var boxCount = 0
        for _ in 0..<iterations {
            autoreleasepool {
                let layout = measure(presentation, width: textWidth)
                samples.append(micros(layout.duration))
                boxCount = layout.boxes.count
            }
        }
        let slowest = samples.indices.max { samples[$0] < samples[$1] } ?? 0
        let first = samples[0]
        samples.sort()
        let median = samples[samples.count / 2]
        let p95 = samples[Int(Double(samples.count) * 0.95)]
        print(String(format: "%-9@ %3d boxes · first %.0f µs · median %.0f µs · p95 %.0f µs · max %.0f µs (iteration %d)",
                     name as NSString, boxCount, first, median, p95, samples.last ?? 0, slowest))
    }
}

/// Renders the morph at a few progress values to PNG files, so the visuals can be checked without a human.
func runSnapshots(directory: String) throws {
    let chars = parseSource(sampleSource)
    let source = measure(sourcePresentation(chars), width: textWidth)
    let rendered = measure(renderedPresentation(chars), width: textWidth)
    let morph = MorphView(chars: chars, source: source, rendered: rendered)
    morph.frame = NSRect(x: 0, y: 0, width: 720, height: 216)
    let window = NSWindow(contentRect: morph.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = morph
    for t in [0.0, 0.25, 0.5, 0.75, 1.0] {
        morph.progress = CGFloat(t)
        let url = URL(fileURLWithPath: directory).appendingPathComponent(String(format: "morph-%03d.png", Int(t * 100)))
        try morph.writeSnapshot(to: url)
        print("wrote \(url.path)")
    }
}

func runApp() {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)

    let mainMenu = NSMenu()
    let appItem = NSMenuItem()
    mainMenu.addItem(appItem)
    let appMenu = NSMenu()
    appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    appItem.submenu = appMenu
    app.mainMenu = mainMenu

    let chars = parseSource(sampleSource)
    let source = measure(sourcePresentation(chars), width: textWidth)
    let rendered = measure(renderedPresentation(chars), width: textWidth)

    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 720, height: 280),
        styleMask: [.titled, .closable, .miniaturizable],
        backing: .buffered,
        defer: false
    )
    window.title = "Torph glyph morph spike"
    window.center()

    let content = NSView(frame: window.contentView!.bounds)
    content.autoresizingMask = [.width, .height]

    let morph = MorphView(chars: chars, source: source, rendered: rendered)
    morph.frame = NSRect(x: 0, y: 64, width: 720, height: 216)
    morph.autoresizingMask = [.width, .height]

    let slider = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    slider.frame = NSRect(x: 16, y: 34, width: 300, height: 20)
    let toggle = NSButton(title: "Morph (space)", target: nil, action: nil)
    toggle.frame = NSRect(x: 328, y: 30, width: 130, height: 28)
    let toggleCA = NSButton(title: "Morph via CA (c)", target: nil, action: nil)
    toggleCA.frame = NSRect(x: 462, y: 30, width: 150, height: 28)
    let label = NSTextField(labelWithString: "")
    label.frame = NSRect(x: 16, y: 8, width: 690, height: 18)
    label.font = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    label.textColor = .secondaryLabelColor
    label.lineBreakMode = .byTruncatingTail

    let measureLine = String(
        format: "measure: source %.0f µs (%d boxes), rendered %.0f µs (%d boxes) · %d layers",
        micros(source.duration), source.boxes.count, micros(rendered.duration), rendered.boxes.count, morph.layerCount
    )
    label.stringValue = measureLine
    print(measureLine)

    final class Controller: NSObject {
        let morph: MorphView
        let slider: NSSlider
        let label: NSTextField
        let measureLine: String
        var target: CGFloat = 1
        init(morph: MorphView, slider: NSSlider, label: NSTextField, measureLine: String) {
            self.morph = morph
            self.slider = slider
            self.label = label
            self.measureLine = measureLine
        }
        @objc func toggle(_ sender: Any?) {
            morph.animate(to: target)
            target = target == 1 ? 0 : 1
        }
        @objc func toggleCA(_ sender: Any?) {
            morph.animateWithCoreAnimation(to: target)
            target = target == 1 ? 0 : 1
        }
        @objc func scrub(_ sender: NSSlider) {
            morph.stopAnimation()
            morph.progress = CGFloat(sender.doubleValue)
            target = sender.doubleValue < 0.5 ? 1 : 0
        }
    }
    let controller = Controller(morph: morph, slider: slider, label: label, measureLine: measureLine)
    slider.target = controller
    slider.action = #selector(Controller.scrub(_:))
    toggle.target = controller
    toggle.action = #selector(Controller.toggle(_:))
    toggle.keyEquivalent = " "
    toggleCA.target = controller
    toggleCA.action = #selector(Controller.toggleCA(_:))
    toggleCA.keyEquivalent = "c"
    morph.onProgressChange = { [weak slider] t in slider?.doubleValue = Double(t) }
    morph.onAnimationEnd = { [weak label] stats in
        print(stats.summary)
        label?.stringValue = stats.summary
    }

    content.addSubview(morph)
    content.addSubview(slider)
    content.addSubview(toggle)
    content.addSubview(toggleCA)
    content.addSubview(label)
    window.contentView = content
    window.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)

    if CommandLine.arguments.contains("--auto") {
        // Play a display-link round trip, then a Core Animation round trip, then quit.
        var rounds = 0
        morph.onAnimationEnd = { stats in
            print(stats.summary)
            rounds += 1
            switch rounds {
            case 1: DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { controller.toggle(nil) }
            case 2, 3: DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { controller.toggleCA(nil) }
            default: DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { app.terminate(nil) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { controller.toggle(nil) }
    }

    app.run()
}

if CommandLine.arguments.contains("--bench") {
    runBench(iterations: 300)
} else if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
    try runSnapshots(directory: CommandLine.arguments[index + 1])
} else {
    runApp()
}
