import SwiftUI

struct PickerView: View {
    @ObservedObject var model: PickerModel
    @ObservedObject var settings: ShortcutSettings
    @FocusState private var searchFocused: Bool

    private let cell: CGFloat = 36
    private let spacing: CGFloat = 4

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            grid
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .onAppear { searchFocused = true }
        .onChange(of: model.presentation) { searchFocused = true }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Lucide icons", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: Grid

    private var grid: some View {
        Group {
            if model.results.isEmpty {
                Text("No icons match “\(model.query)”")
                    .foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.fixed(cell), spacing: spacing), count: PickerModel.columns),
                            spacing: spacing
                        ) {
                            ForEach(Array(model.results.enumerated()), id: \.element.id) { index, icon in
                                iconCell(icon, selected: index == model.selection)
                                    .onTapGesture {
                                        model.confirm(settings.pasteKind(forClickWith: NSEvent.modifierFlags), index: index)
                                    }
                            }
                        }
                        .padding(10)
                    }
                    // Cells are identified by icon name (ForEach id), so scroll by name too.
                    .onChange(of: model.selection) {
                        if let icon = model.selectedIcon { proxy.scrollTo(icon.id) }
                    }
                    .onChange(of: model.query) {
                        if let first = model.results.first { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
            }
        }
    }

    private func iconCell(_ icon: LucideIcon, selected: Bool) -> some View {
        Image(nsImage: model.store.image(for: icon))
            .renderingMode(.template)
            .resizable()
            .frame(width: 20, height: 20)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .frame(width: cell, height: cell)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
            .help(icon.name)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if let icon = model.selectedIcon {
                Text(icon.name)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text("\(settings[.pasteName].display) name   \(settings[.pasteSVGCode].display) SVG   \(settings[.pasteSVGFile].display) file")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
