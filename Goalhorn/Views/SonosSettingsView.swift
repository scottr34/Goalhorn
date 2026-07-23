import SwiftUI

/// Choose where the goal song plays and, for Sonos, discover/select the speaker.
struct SonosSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var discovery = SonosDiscovery()

    @State private var manualIP: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Play Goal Song On") {
                    Picker("Audio output", selection: $settings.audioTarget) {
                        ForEach(AudioTarget.allCases) { target in
                            Text(target.displayName).tag(target)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if settings.audioTarget == .sonos {
                    sonosSections
                } else {
                    Section {
                        Text("The goal song will play through this iPhone's speaker.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Speaker")
        }
    }

    @ViewBuilder
    private var sonosSections: some View {
        if let selected = settings.sonosDevice {
            Section("Selected Speaker") {
                HStack {
                    Image(systemName: "hifispeaker.fill").foregroundStyle(.red)
                    VStack(alignment: .leading) {
                        Text(selected.roomName).font(.headline)
                        Text(selected.modelName ?? selected.ipAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Clear") { settings.sonosDevice = nil }
                        .foregroundStyle(.red)
                }
            }

            Section("Volume") {
                HStack {
                    Image(systemName: "speaker.fill")
                    Slider(
                        value: Binding(
                            get: { Double(settings.sonosVolume) },
                            set: { settings.sonosVolume = Int($0) }
                        ),
                        in: 0...100,
                        step: 1
                    )
                    Image(systemName: "speaker.wave.3.fill")
                    Text("\(settings.sonosVolume)")
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }

        Section {
            Button {
                Task { await discovery.scan() }
            } label: {
                HStack {
                    Label(discovery.isScanning ? "Scanning…" : "Scan for Sonos", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    if discovery.isScanning { ProgressView() }
                }
            }
            .disabled(discovery.isScanning)

            if discovery.isScanning {
                ProgressView(value: discovery.progress)
            }

            ForEach(discovery.devices) { device in
                Button {
                    settings.sonosDevice = device
                } label: {
                    HStack {
                        Image(systemName: settings.sonosDevice?.ipAddress == device.ipAddress ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(settings.sonosDevice?.ipAddress == device.ipAddress ? .red : .secondary)
                        VStack(alignment: .leading) {
                            Text(device.roomName)
                            Text("\(device.modelName ?? "Sonos") · \(device.ipAddress)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Discover")
        } footer: {
            if !discovery.isScanning && discovery.devices.isEmpty {
                Text("Make sure your iPhone is on the same Wi-Fi as your Sonos, then scan. You can also enter the speaker's IP address manually below.")
            }
        }

        Section("Enter IP Manually") {
            HStack {
                TextField("192.168.1.50", text: $manualIP)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Use") {
                    let trimmed = manualIP.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { return }
                    settings.sonosDevice = SonosDevice(ipAddress: trimmed, roomName: "Sonos (\(trimmed))", modelName: nil)
                    manualIP = ""
                }
                .disabled(manualIP.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}
