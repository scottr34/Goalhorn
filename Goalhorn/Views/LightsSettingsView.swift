import SwiftUI

/// Grant HomeKit access, pick which bulbs spin, and set the show length.
struct LightsSettingsView: View {
    @EnvironmentObject private var homeKit: HomeKitManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var celebration: CelebrationController

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Light Show") {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Duration")
                            Spacer()
                            Text("\(Int(settings.celebrationDuration))s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $settings.celebrationDuration, in: 3...30, step: 1)
                    }
                    Text("Lights spin red/blue like a rotating goal beacon, then return to how they were.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                lightsSection

                if !settings.selectedLightIDs.isEmpty {
                    Section {
                        Button {
                            testShow()
                        } label: {
                            Label("Test Light Show", systemImage: "play.circle")
                        }
                    }
                }
            }
            .navigationTitle("Lights")
            .onAppear { homeKit.start() }
            .toolbar {
                Button {
                    homeKit.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private var lightsSection: some View {
        switch homeKit.status {
        case .notStarted, .waiting:
            Section {
                HStack {
                    ProgressView()
                    Text("Connecting to HomeKit…")
                        .foregroundStyle(.secondary)
                }
            }
        case .restricted:
            Section {
                ContentUnavailableView {
                    Label("HomeKit Access Needed", systemImage: "lock.fill")
                } description: {
                    Text("Enable HomeKit for Goalhorn in Settings → Privacy & Security → HomeKit to control your lights.")
                }
            }
        case .ready:
            if homeKit.lights.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Lights Found",
                        systemImage: "lightbulb.slash",
                        description: Text("Add color-capable lightbulbs to the Home app, then tap refresh.")
                    )
                }
            } else {
                Section {
                    ForEach(homeKit.lights) { light in
                        lightRow(light)
                    }
                } header: {
                    Text("Choose Lights")
                } footer: {
                    Text("Color bulbs give the full red/blue spin. Others will still flash brightness.")
                }
            }
        }
    }

    private func lightRow(_ light: GoalLight) -> some View {
        Toggle(isOn: binding(for: light)) {
            HStack(spacing: 12) {
                Image(systemName: light.supportsColor ? "lightbulb.led.fill" : "lightbulb.fill")
                    .foregroundStyle(light.supportsColor ? .red : .yellow)
                VStack(alignment: .leading, spacing: 2) {
                    Text(light.name)
                    Text(light.accessoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .tint(.red)
    }

    private func binding(for light: GoalLight) -> Binding<Bool> {
        Binding(
            get: { settings.selectedLightIDs.contains(light.id) },
            set: { isOn in
                if isOn { settings.selectedLightIDs.insert(light.id) }
                else { settings.selectedLightIDs.remove(light.id) }
            }
        )
    }

    private func testShow() {
        let selected = homeKit.lights.filter { settings.selectedLightIDs.contains($0.id) }
        celebration.lightEngine.start(on: selected, duration: 6)
    }
}
