import SwiftUI
import SwiftData

struct AddServerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var host = ""
    @State private var port = 22
    @State private var username = ""
    @State private var authType = AuthType.password
    @State private var password = ""
    @State private var privateKey = ""
    @State private var passphrase = ""
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
                }

                Section("认证方式") {
                    Picker("类型", selection: $authType) {
                        Text("密码").tag(AuthType.password)
                        Text("私钥").tag(AuthType.privateKey)
                    }

                    if authType == .password {
                        SecureField("密码", text: $password)
                    } else {
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
            .navigationTitle("添加服务器")
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
        .frame(minWidth: 420, minHeight: 480)
    }

    private func save() {
        let server = Server(
            displayName: displayName,
            host: host,
            port: port,
            username: username,
            authType: authType
        )
        modelContext.insert(server)

        do {
            switch authType {
            case .password:
                try KeychainHelper.save(key: server.id.uuidString, value: password)
            case .privateKey:
                try KeychainHelper.save(key: server.id.uuidString + ".key", value: privateKey)
                if !passphrase.isEmpty {
                    try KeychainHelper.save(key: server.id.uuidString + ".passphrase", value: passphrase)
                }
            }
            dismiss()
        } catch {
            errorMessage = "Keychain 保存失败: \(error.localizedDescription)"
        }
    }
}
