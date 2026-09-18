import SwiftUI
import CoreLocation

public struct AutoFlightImportSheet: View {
    @ObservedObject var appState: AppState = .shared
    @Environment(\.dismiss) private var dismiss

    @State private var flightNumberInput: String = ""
    @State private var selectedDate: Date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    @State private var isSearching: Bool = false
    @State private var isImporting: Bool = false
    @State private var errorMessage: String? = nil
    @State private var schedules: [TrackedFlightSchedule] = []

    public init() {}

    private var targetDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: selectedDate)
    }

    private var isSearchDisabled: Bool {
        flightNumberInput.trimmingCharacters(in: .whitespaces).isEmpty || isSearching || isImporting
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "airplane.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Auto-Import Real Flight")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        appState.isAutoImportPresented = false
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .padding(5)
                }
                .nativeGlassButton(shape: .circle)
            }

            Text("Enter a real-world flight number and flight date to automatically download its actual radar track, populate origin/destination airports, and fit navigation waypoints.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Input Fields Card
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Flight Number")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    TextField("e.g. KL591 or AFL462", text: $flightNumberInput)
                        .liquidGlassInputField(cornerRadius: 12)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 175)
                        .onSubmit {
                            Task { await searchSchedules() }
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Flight Date")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    DatePicker("", selection: $selectedDate, displayedComponents: [.date])
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(" ")
                        .font(.caption)

                    Button(action: { Task { await searchSchedules() } }) {
                        HStack(spacing: 6) {
                            if isSearching {
                                ProgressView()
                                    .scaleEffect(0.65)
                            } else {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text("Find Flight")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                    }
                    .nativeGlassButton(prominent: false, shape: .roundedRectangle(radius: 12))
                    .disabled(isSearchDisabled)
                }
            }
            .padding(12)
            .liquidGlassCard(cornerRadius: 12)

            // Error Message
            if let error = errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 4)
            }

            // Results Section
            if !schedules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available Flights (\(schedules.count)):")
                        .font(.subheadline)
                        .fontWeight(.bold)

                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(schedules) { schedule in
                                ScheduleRow(schedule: schedule, isImporting: isImporting) {
                                    Task { await importSchedule(schedule) }
                                }
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 200)
                }
            } else if !isSearching && errorMessage == nil && !flightNumberInput.isEmpty {
                VStack(alignment: .center, spacing: 6) {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("Click \"Find Flight\" to query open radar records.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    Spacer()
                }
                .frame(height: 60)
            }

            Spacer()
        }
        .padding(22)
        .frame(width: 520, height: 400)
        .liquidGlassModalPanel(cornerRadius: 24)
    }

    private func searchSchedules() async {
        let rawIdent = flightNumberInput.trimmingCharacters(in: .whitespaces)
        guard !rawIdent.isEmpty else { return }

        isSearching = true
        errorMessage = nil
        schedules = []

        let targetDate = targetDateString

        do {
            let found = try await FlightTrackerService.shared.fetchAvailableSchedules(
                for: rawIdent,
                targetDate: targetDate
            )

            if found.isEmpty {
                // Try searching without date filter if strictly filtering yielded no flight
                let allRecent = try await FlightTrackerService.shared.fetchAvailableSchedules(
                    for: rawIdent,
                    targetDate: nil
                )
                if allRecent.isEmpty {
                    errorMessage = "No track data found for \(rawIdent). Please verify flight number."
                } else {
                    self.schedules = allRecent
                    errorMessage = "No flights found on \(targetDate), showing recent flights instead:"
                }
            } else {
                self.schedules = found
            }
        } catch {
            errorMessage = "Failed to fetch flight data: \(error.localizedDescription)"
        }

        isSearching = false
    }

    private func importSchedule(_ schedule: TrackedFlightSchedule) async {
        isImporting = true
        errorMessage = nil

        do {
            let result = try await FlightTrackerService.shared.fetchTrackCoordinates(from: schedule.kmlURL)
            guard !result.coordinates.isEmpty else {
                errorMessage = "Track contains no radar points."
                isImporting = false
                return
            }

            // Apply to AppState
            let origin = result.originICAO.isEmpty ? schedule.departureICAO : result.originICAO
            let dest = result.destICAO.isEmpty ? schedule.arrivalICAO : result.destICAO

            appState.applyImportedFlight(
                originICAO: origin,
                destICAO: dest,
                coordinates: result.coordinates
            )

            // Dismiss modal upon successful import
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                appState.isAutoImportPresented = false
            }
            dismiss()
        } catch {
            errorMessage = "Failed to download track: \(error.localizedDescription)"
        }

        isImporting = false
    }
}

private struct ScheduleRow: View {
    let schedule: TrackedFlightSchedule
    let isImporting: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(schedule.flightIdent)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.accentColor)

                    Text(schedule.displayTitle)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.primary)

                    if let reg = schedule.aircraftRegistration, !reg.isEmpty {
                        Text(reg)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(Color.orange.opacity(0.15))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(Color.orange.opacity(0.4), lineWidth: 0.8)
                            )
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            Button(action: onSelect) {
                HStack(spacing: 5) {
                    if isImporting {
                        ProgressView()
                            .scaleEffect(0.6)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("Import Route")
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .nativeGlassButton(prominent: false, shape: .roundedRectangle(radius: 12))
            .disabled(isImporting)
        }
        .padding(10)
        .liquidGlassCard(cornerRadius: 10)
    }
}
