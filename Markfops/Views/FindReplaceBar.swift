import AppKit
import Observation
import SwiftUI

@Observable
@MainActor
final class FindController {
    var isVisible = false
    var showsReplace = false
    var searchText = ""
    var replaceText = ""
    var lastMatchFound = true
    var focusRequestID = 0
    var activeMode: EditMode = .edit

    @ObservationIgnored weak var editorBridge: EditorBridge?
    @ObservationIgnored weak var previewBridge: PreviewBridge?

    func attach(editorBridge: EditorBridge, previewBridge: PreviewBridge, mode: EditMode) {
        self.editorBridge = editorBridge
        self.previewBridge = previewBridge
        activeMode = mode
    }

    func showFind() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isVisible = true
            showsReplace = false
        }
        lastMatchFound = true
        focusRequestID += 1
    }

    func showReplace() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            isVisible = true
            showsReplace = activeMode == .edit
        }
        lastMatchFound = true
        focusRequestID += 1
    }

    func hide() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            isVisible = false
            showsReplace = false
        }
        lastMatchFound = true
    }

    func toggleReplace() {
        guard activeMode == .edit else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showsReplace.toggle()
        }
        focusRequestID += 1
    }

    func findNext() {
        find(forward: true)
    }

    func findPrevious() {
        find(forward: false)
    }

    func useSelectionForFind() {
        guard activeMode == .edit,
              let selection = editorBridge?.selectedText(),
              !selection.isEmpty else { return }
        searchText = selection
        showFind()
        findNext()
    }

    func replaceCurrent() {
        guard activeMode == .edit, !searchText.isEmpty else { return }
        lastMatchFound = editorBridge?.replaceCurrentMatch(find: searchText, replace: replaceText) ?? false
    }

    func replaceAll() {
        guard activeMode == .edit, !searchText.isEmpty else { return }
        let replacements = editorBridge?.replaceAll(find: searchText, replace: replaceText) ?? 0
        lastMatchFound = replacements > 0
    }

    private func find(forward: Bool) {
        guard !searchText.isEmpty else {
            lastMatchFound = true
            return
        }

        switch activeMode {
        case .edit:
            lastMatchFound = editorBridge?.find(searchText, forward: forward) ?? false
        case .preview:
            previewBridge?.find(searchText, forward: forward) { [weak self] found in
                self?.lastMatchFound = found
            }
        }
    }
}

struct FindReplaceBar: View {
    @Bindable var controller: FindController
    @FocusState private var focusedField: Field?

    private enum Field {
        case find
        case replace
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow

            if controller.showsReplace && controller.activeMode == .edit {
                replaceRow
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !controller.lastMatchFound && !controller.searchText.isEmpty {
                statusLabel
            }
        }
        .padding(12)
        .background(
            GlassEffectView(material: .hudWindow, blendingMode: .withinWindow)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(0.03))
        )
        .shadow(color: .black.opacity(0.05), radius: 14, y: 7)
        .frame(maxWidth: 760)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .onExitCommand {
            controller.hide()
        }
        .onAppear {
            focusedField = .find
        }
        .onChange(of: controller.focusRequestID) { _, _ in
            focusedField = controller.showsReplace ? .replace : .find
        }
        .transition(
            .asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            )
        )
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            findControls
            replaceToggle
            Spacer(minLength: 0)
            closeButton
        }
    }

    private var replaceRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                replaceField
                replaceButtons
            }

            VStack(alignment: .leading, spacing: 10) {
                replaceField
                replaceButtons
            }
        }
    }

    private var findControls: some View {
        HStack(spacing: 10) {
            TextField("Find", text: $controller.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .focused($focusedField, equals: .find)
                .onSubmit { controller.findNext() }

            Button(action: controller.findPrevious) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)

            Button(action: controller.findNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var replaceToggle: some View {
        if controller.activeMode == .edit {
            if controller.showsReplace {
                Button("Replace") {
                    controller.toggleReplace()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else {
                Button("Replace") {
                    controller.toggleReplace()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var replaceButtons: some View {
        HStack(spacing: 10) {
            Button("Replace", action: controller.replaceCurrent)
            Button("All", action: controller.replaceAll)
        }
    }

    private var replaceField: some View {
        TextField("Replace", text: $controller.replaceText)
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: .infinity)
            .focused($focusedField, equals: .replace)
            .onSubmit { controller.replaceCurrent() }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if !controller.lastMatchFound && !controller.searchText.isEmpty {
            Text("No Match")
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private var closeButton: some View {
        Button(action: controller.hide) {
            Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
    }
}

private struct GlassEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.isEmphasized = false
    }
}
