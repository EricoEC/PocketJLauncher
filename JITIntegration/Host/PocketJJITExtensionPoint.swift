import ExtensionFoundation

@available(iOS 26.0, *)
extension AppExtensionPoint {
    @Definition
    static var pocketJJITHelper: AppExtensionPoint {
        Name("PocketJJITHelper")
    }
}
