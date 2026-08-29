import SwiftUI

/// Grant HomeKit access, pick which bulbs spin, choose the beacon colours, and
/// set the show length.
struct LightsSettingsView: View {
    @EnvironmentObject private var homeKit: HomeKitManager
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var celebration: CelebrationController

    @State private var isAddingColor = false

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
                    Text("Lights spin like a rotating goal beacon, then return to how they were.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                colorsSection
                quickSetsSection
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
            .onChange(of: homeKit.lights.count) { _, count in
                // Lights just became available — put them back if a previous
                // celebration was killed before it could clean up.
                if count > 0 { celebration.restoreInterruptedShow() }
            }
            .toolbar {
                Button {
                    homeKit.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .sheet(isPresented: $isAddingColor) {
                AddGoalColorSheet { color in
                    settings.goalColors.append(color)
                }
            }
        }
    }

    // MARK: - Colours

    private var colorsSection: some View {
        Section {
            ForEach(settings.goalColors) { color in
                HStack(spacing: 12) {
                    swatch(color)
                    Text(color.name)
                    Spacer()
                    if color.isOff {
                        Text("dark beat")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { offsets in
                settings.goalColors.remove(atOffsets: offsets)
                if settings.goalColors.isEmpty {
                    settings.goalColors = GoalLightColor.defaultSequence
                }
            }
            .onMove { source, destination in
                settings.goalColors.move(fromOffsets: source, toOffset: destination)
            }

            Button {
                isAddingColor = true
            } label: {
                Label("Add Color", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Beacon Colors")
                Spacer()
                EditButton()
                    .font(.caption)
                    .textCase(nil)
            }
        } footer: {
            Text("Cycles \(settings.goalColors.sequenceDescription), about a second on each. Drag to reorder, swipe to remove.")
        }
    }

    private var quickSetsSection: some View {
        Section("Quick Sets") {
            ForEach(GoalLightSequence.presets) { preset in
                Button {
                    settings.goalColors = preset.freshColors
                } label: {
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            ForEach(Array(preset.colors.enumerated()), id: \.offset) { _, color in
                                swatch(color, size: 16)
                            }
                        }
                        Text(preset.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        if settings.goalColors.matchesSequence(preset.colors) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    private func swatch(_ color: GoalLightColor, size: CGFloat = 22) -> some View {
        Circle()
            .fill(color.swatch)
            .frame(width: size, height: size)
            .overlay(
                Circle().strokeBorder(Color.primary.opacity(color.isOff ? 0.35 : 0.15), lineWidth: 1)
            )
    }

    // MARK: - Lights

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
                    Text("Color bulbs give the full colour spin. Others will still flash brightness.")
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
        celebration.lightEngine.start(on: selected, colors: settings.goalColors, duration: 6)
    }
}

/// Preset swatches plus a full colour picker, for adding a beat to the sequence.
private struct AddGoalColorSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onAdd: (GoalLightColor) -> Void

    @State private var customColor: Color = .red

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 16)]

    var body: some View {
        NavigationStack {
            Form {
                Section("Presets") {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(GoalLightColor.presets) { preset in
                            Button {
                                onAdd(preset.fresh())
                                dismiss()
                            } label: {
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(preset.swatch)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle().strokeBorder(
                                                Color.primary.opacity(preset.isOff ? 0.35 : 0.15),
                                                lineWidth: 1
                                            )
                                        )
                                    Text(preset.name)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    ColorPicker("Pick a color", selection: $customColor, supportsOpacity: false)
                    Button("Add This Color") {
                        onAdd(GoalLightColor(custom: customColor))
                        dismiss()
                    }
                } header: {
                    Text("Custom")
                } footer: {
                    Text("Bulbs reproduce hue and saturation only — brightness is driven by the sweep.")
                }
            }
            .navigationTitle("Add Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
