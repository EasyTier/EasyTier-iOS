import SwiftUI

struct SettingsView: View {
    @AppStorage("logLevel") var logLevel: String = "info"
    @AppStorage("statusRefreshInterval") var statusRefreshInterval: Double = 1.0
    @AppStorage("useRealDeviceNameAsDefault") var useRealDeviceNameAsDefault: Bool = true

    let logLevels = ["trace", "debug", "info", "warn", "error"]

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("General") {
                    Picker("Log Level", selection: $logLevel) {
                        ForEach(logLevels, id: \.self) { level in
                            Text(level.uppercased()).tag(level)
                        }
                    }
                    Toggle("Use Device Name as Default", isOn: $useRealDeviceNameAsDefault)
                    LabeledContent("Refresh Interval") {
                        HStack {
                            TextField(
                                "1.0",
                                value: $statusRefreshInterval,
                                formatter: NumberFormatter()
                            )
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            Text("s")
                        }
                    }
                }

                Section("About") {
                    LabeledContent("App") {
                        Text("EasyTier")
                    }
                    LabeledContent("Version") {
                        Text(appVersion)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
