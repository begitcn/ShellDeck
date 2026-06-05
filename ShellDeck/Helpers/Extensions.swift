import SwiftUI

extension View {
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        condition ? AnyView(transform(self)) : AnyView(self)
    }

    func `if`<TrueContent: View, FalseContent: View>(
        _ condition: Bool,
        ifTrue: (Self) -> TrueContent,
        ifFalse: (Self) -> FalseContent
    ) -> some View {
        condition ? AnyView(ifTrue(self)) : AnyView(ifFalse(self))
    }
}

extension Color {
    static let appGreen = Color.green
    static let appRed = Color.red
    static let appOrange = Color.orange
    static let appGray = Color.gray.opacity(0.3)
}

extension Notification.Name {
    static let serverDisconnected = Notification.Name("com.chaogeek.shelldeck.serverDisconnected")
    static let serverConnected = Notification.Name("com.chaogeek.shelldeck.serverConnected")
}
