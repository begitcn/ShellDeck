import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appTheme") private var appTheme: String = AppTheme.dark.rawValue
    @State private var updateService = UpdateService.shared
    
    @State private var selectedTab: SettingsTab = .general
    
    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "通用与外观"
        case about = "关于与更新"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .general: return "paintpalette"
            case .about: return "info.circle"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top tab selector (Mac native look)
            HStack(spacing: 20) {
                ForEach(SettingsTab.allCases) { tab in
                    Button(action: { selectedTab = tab }) {
                        VStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 20))
                                .foregroundStyle(selectedTab == tab ? .blue : .secondary)
                            Text(tab.rawValue)
                                .font(.caption)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        }
                        .frame(width: 80)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(selectedTab == tab ? Color.primary.opacity(0.06) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("关闭")
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Tab contents
            Group {
                switch selectedTab {
                case .general:
                    generalSettingsTab
                case .about:
                    aboutUpdatesTab
                }
            }
            .frame(height: 340)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        }
        .frame(width: 480, height: 400)
        .onAppear {
            // Reset checkStatus back to idle/loaded state when opening settings to avoid stale state.
            if updateService.checkStatus == .upToDate {
                updateService.resetStatus()
            }
        }
    }
    
    // MARK: - General Settings Tab
    
    private var generalSettingsTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text("外观设置")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    
                    Text("选择您偏好的 ShellDeck 界面主题样式。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    HStack(spacing: 24) {
                        ForEach(AppTheme.allCases) { theme in
                            Button(action: { appTheme = theme.rawValue }) {
                                VStack(spacing: 12) {
                                    ZStack(alignment: .topLeading) {
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(theme == .dark ? Color.black : Color.white)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .stroke(appTheme == theme.rawValue ? Color.blue : Color.primary.opacity(0.1), lineWidth: appTheme == theme.rawValue ? 2 : 1)
                                            )
                                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                                        
                                        // Preview accent (Traffic lights) perfectly placed inside the card bounds
                                        HStack(spacing: 4) {
                                            Circle().fill(Color.red.opacity(0.8)).frame(width: 6, height: 6)
                                            Circle().fill(Color.yellow.opacity(0.8)).frame(width: 6, height: 6)
                                            Circle().fill(Color.green.opacity(0.8)).frame(width: 6, height: 6)
                                        }
                                        .padding(8)
                                        
                                        // Centered theme icon
                                        Image(systemName: theme.icon)
                                            .font(.system(size: 22))
                                            .foregroundStyle(theme == .dark ? .white : .black)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    }
                                    .frame(width: 120, height: 80)
                                    
                                    Text(theme.displayName)
                                        .font(.subheadline)
                                        .fontWeight(appTheme == theme.rawValue ? .semibold : .regular)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .padding(20)
            }

        }
        .formStyle(.grouped)
    }
    
    // MARK: - About & Updates Tab
    
    private var aboutUpdatesTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // App Branding Section
                    VStack(spacing: 8) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(0.15), radius: 5, x: 0, y: 3)
                        
                        Text("ShellDeck")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        Text("Version \(updateService.currentVersion)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 16)
                    
                    Divider()
                        .padding(.horizontal, 16)
                    
                    // Dynamic Update Status Panel
                    VStack(spacing: 12) {
                        switch updateService.checkStatus {
                        case .idle:
                            idleStatusView
                            
                        case .checking:
                            checkingStatusView
                            
                        case .upToDate:
                            upToDateStatusView
                            
                        case .error(let message):
                            errorStatusView(message)
                            
                        case .updateAvailable(let version, let notes, let downloadUrl, let releaseUrl):
                            updateAvailableView(version: version, notes: notes, downloadUrl: downloadUrl, releaseUrl: releaseUrl)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }
    
    // MARK: - Status Panel Views
    
    private var idleStatusView: some View {
        VStack(spacing: 12) {
            Text("点击下方按钮检查 ShellDeck 是否有新版本可用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("检查更新") {
                Task {
                    await updateService.checkForUpdates(manual: true)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.vertical, 8)
    }
    
    private var checkingStatusView: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            
            Text("正在检查最新版本...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
    }
    
    private var upToDateStatusView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                
                Text("已是最新版本")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            
            Text("您当前运行的是最新版 ShellDeck。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button("重新检查") {
                Task {
                    await updateService.checkForUpdates(manual: true)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
    }
    
    private func errorStatusView(_ message: String) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)
                
                Text("检查更新失败")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            
            Button("重试") {
                Task {
                    await updateService.checkForUpdates(manual: true)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.top, 4)
        }
        .padding(.vertical, 10)
    }
    
    private func updateAvailableView(version: String, notes: String?, downloadUrl: String?, releaseUrl: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("发现新版本 v\(version)！")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("当前版本: v\(updateService.currentVersion)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if let releaseUrl = releaseUrl, let url = URL(string: releaseUrl) {
                    Link(destination: url) {
                        Label("在网页查看", systemImage: "safari")
                            .font(.caption)
                    }
                }
            }
            .padding(.bottom, 4)
            
            // Download and interactive updates UI
            if updateService.isDownloading {
                VStack(spacing: 8) {
                    HStack {
                        Text("正在下载更新包...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(updateService.downloadProgress * 100))%")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.blue)
                    }
                    ProgressView(value: updateService.downloadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                    
                    Button("取消") {
                        updateService.cancelDownload()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(8)
            } else if updateService.downloadedFileUrl != nil {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    
                    Text("下载完成，正在自动静默安装并重启应用...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
                .padding(16)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.06))
                .cornerRadius(8)
            } else {
                HStack {
                    Spacer()
                    Button("下载并安装") {
                        updateService.downloadAndInstall()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    Spacer()
                }
                .padding(.top, 4)
            }
            
            if let downloadError = updateService.downloadError {
                Text("下载失败: \(downloadError)")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .bold()
            }
        }
        .padding(16)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    SettingsView()
}
