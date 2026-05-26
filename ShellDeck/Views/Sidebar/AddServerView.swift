import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AddServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \ServerGroup.sortOrder) private var groups: [ServerGroup]

    var server: Server?

    @State private var displayName = ""
    @State private var selectedGroup: ServerGroup?
    @State private var host = ""
    @State private var port = 22
    @State private var username = ""
    @State private var authType = AuthType.password
    @State private var originalAuthType: AuthType = .password
    @State private var password = ""
    @State private var privateKey = ""
    @State private var passphrase = ""
    @State private var showFilePicker = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称（可选）", text: $displayName)
                    TextField("主机地址", text: $host)
                        .autocorrectionDisabled()
                    HStack {
                        TextField("端口", value: $port, format: .number)
                            .frame(width: 80)
                        Spacer()
                    }
                    TextField("用户名", text: $username)
                        .autocorrectionDisabled()
                    if !groups.isEmpty {
                        Picker("分组", selection: $selectedGroup) {
                            Text("无").tag(Optional<ServerGroup>.none)
                            ForEach(groups) { group in
                                Text(group.name).tag(Optional.some(group))
                            }
                        }
                    }
                }

                Section("认证方式") {
                    Picker("类型", selection: $authType) {
                        Text("密码").tag(AuthType.password)
                        Text("私钥").tag(AuthType.privateKey)
                    }

                    if authType == .password {
                        SecureField("密码", text: $password)
                    } else {
                        HStack {
                            Button("选择密钥文件...") { showFilePicker = true }
                                .controlSize(.small)
                            Spacer()
                        }
                        TextEditor(text: $privateKey)
                            .font(.body.monospaced())
                            .frame(minHeight: 150)
                            .overlay {
                                if privateKey.isEmpty {
                                    Text("粘贴你的私钥内容（PEM 格式）")
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                }
                            }
                        SecureField("私钥密码（可选）", text: $passphrase)
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(server == nil ? "添加服务器" : "编辑服务器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(host.isEmpty || username.isEmpty)
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.plainText, UTType(filenameExtension: "pem"), UTType(filenameExtension: "key")].compactMap { $0 }
        ) { result in
            switch result {
            case .success(let url):
                guard url.startAccessingSecurityScopedResource() else {
                    errorMessage = "无法访问所选文件"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    privateKey = try String(contentsOf: url, encoding: .utf8)
                } catch {
                    errorMessage = "无法读取文件: \(error.localizedDescription)"
                }
            case .failure(let error):
                errorMessage = "文件选择失败: \(error.localizedDescription)"
            }
        }
        .frame(minWidth: 420, minHeight: 480)
        .onAppear {
            loadServerData()
        }
    }

    private func loadServerData() {
        guard let server else { return }
        displayName = server.displayName
        host = server.host
        port = server.port
        username = server.username
        authType = server.authTypeEnum
        originalAuthType = server.authTypeEnum
        selectedGroup = server.group

        if authType == .password {
            password = (try? KeychainHelper.read(key: server.id.uuidString)) ?? ""
        } else {
            privateKey = (try? KeychainHelper.read(key: server.id.uuidString + ".key")) ?? ""
            passphrase = (try? KeychainHelper.read(key: server.id.uuidString + ".passphrase")) ?? ""
        }
    }

    private func save() {
        if let server {
            server.displayName = displayName
            server.host = host
            server.port = port
            server.username = username
            server.authTypeEnum = authType
            server.group = selectedGroup

            if authType != originalAuthType {
                KeychainHelper.delete(key: server.id.uuidString)
                KeychainHelper.delete(key: server.id.uuidString + ".key")
                KeychainHelper.delete(key: server.id.uuidString + ".passphrase")
            }

            do {
                switch authType {
                case .password:
                    if !password.isEmpty {
                        try KeychainHelper.save(key: server.id.uuidString, value: password)
                    }
                case .privateKey:
                    if !privateKey.isEmpty {
                        try KeychainHelper.save(key: server.id.uuidString + ".key", value: privateKey)
                    }
                    if !passphrase.isEmpty {
                        try KeychainHelper.save(key: server.id.uuidString + ".passphrase", value: passphrase)
                    }
                }
                dismiss()
            } catch {
                errorMessage = "Keychain 保存失败: \(error.localizedDescription)"
            }
        } else {
            let newServer = Server(
                displayName: displayName,
                host: host,
                port: port,
                username: username,
                authType: authType
            )
            newServer.group = selectedGroup
            let allServers = (try? modelContext.fetch(FetchDescriptor<Server>())) ?? []
            newServer.sortOrder = allServers.filter { $0.group?.id == selectedGroup?.id }.count
            modelContext.insert(newServer)

            do {
                switch authType {
                case .password:
                    try KeychainHelper.save(key: newServer.id.uuidString, value: password)
                case .privateKey:
                    try KeychainHelper.save(key: newServer.id.uuidString + ".key", value: privateKey)
                    if !passphrase.isEmpty {
                        try KeychainHelper.save(key: newServer.id.uuidString + ".passphrase", value: passphrase)
                    }
                }
                dismiss()
            } catch {
                errorMessage = "Keychain 保存失败: \(error.localizedDescription)"
            }
        }
    }
}
