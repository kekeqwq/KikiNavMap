import SwiftUI

public struct AirportSearchField: View {
    let title: String
    let iconColor: Color
    @Binding var text: String
    let selectedAirport: Airport?
    let onSelect: (Airport) -> Void

    @ObservedObject private var navData = NavDataManager.shared
    @State private var isShowingSuggestions: Bool = false
    @State private var suggestions: [Airport] = []
    @State private var highlightedIndex: Int = 0
    @State private var suppressSuggestions: Bool = false
    @FocusState private var isFocused: Bool

    public init(
        title: String,
        iconColor: Color,
        text: Binding<String>,
        selectedAirport: Airport?,
        onSelect: @escaping (Airport) -> Void
    ) {
        self.title = title
        self.iconColor = iconColor
        self._text = text
        self.selectedAirport = selectedAirport
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(iconColor)
                .frame(width: 8, height: 8)

            TextField(title, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .textCase(.uppercase)
                .frame(minWidth: 90, maxWidth: 140)
                .onChange(of: text) { _, newValue in
                    if suppressSuggestions || !isFocused {
                        suppressSuggestions = false
                        isShowingSuggestions = false
                        suggestions = []
                        return
                    }
                    updateSuggestions(for: newValue)
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused {
                        isShowingSuggestions = false
                        suggestions = []
                    }
                }
                .onSubmit {
                    commitSelection()
                }
                .onKeyPress(.downArrow) {
                    if !suggestions.isEmpty {
                        highlightedIndex = min(suggestions.count - 1, highlightedIndex + 1)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.upArrow) {
                    if !suggestions.isEmpty {
                        highlightedIndex = max(0, highlightedIndex - 1)
                        return .handled
                    }
                    return .ignored
                }
                .onKeyPress(.escape) {
                    isShowingSuggestions = false
                    suggestions = []
                    return .handled
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isFocused ? iconColor.opacity(0.8) : Color.clear, lineWidth: 1.5)
        )
        // Inline Non-Intrusive Floating Dropdown (Does NOT steal focus!)
        .overlay(alignment: .topLeading) {
            if isFocused && isShowingSuggestions && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, apt in
                        Button(action: { choose(apt) }) {
                            HStack(spacing: 6) {
                                Text(apt.id)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(index == highlightedIndex ? .white : .accentColor)

                                if !apt.iata.isEmpty {
                                    Text(apt.iata)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(index == highlightedIndex ? Color.white.opacity(0.2) : Color.accentColor.opacity(0.12))
                                        )
                                        .foregroundColor(index == highlightedIndex ? .white : .accentColor)
                                }

                                Text(apt.city.isEmpty ? apt.name : "\(apt.name), \(apt.city)")
                                    .font(.system(size: 11))
                                    .foregroundColor(index == highlightedIndex ? .white : .primary)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(index == highlightedIndex ? Color.accentColor : Color.clear)
                        )
                    }
                }
                .padding(6)
                .frame(width: 280)
                .liquidGlass(in: RoundedRectangle(cornerRadius: 12, style: .continuous), interactive: true)
                .offset(y: 36)
                .zIndex(200)
            }
        }
    }

    private func updateSuggestions(for query: String) {
        guard isFocused else {
            suggestions = []
            isShowingSuggestions = false
            return
        }
        let clean = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count >= 1 else {
            suggestions = []
            isShowingSuggestions = false
            return
        }
        suggestions = navData.searchAirports(query: clean)
        highlightedIndex = 0
        isShowingSuggestions = !suggestions.isEmpty
    }

    private func commitSelection() {
        if !suggestions.isEmpty && highlightedIndex < suggestions.count {
            choose(suggestions[highlightedIndex])
        } else if let exact = navData.airportMap[text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()] {
            choose(exact)
        } else {
            isShowingSuggestions = false
            suggestions = []
        }
    }

    private func choose(_ airport: Airport) {
        suppressSuggestions = true
        text = airport.id
        isShowingSuggestions = false
        suggestions = []
        onSelect(airport)
    }
}
