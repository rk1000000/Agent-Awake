public enum MacPowerProfile {
    public static func recommendedAdapterWatts(forModelIdentifier modelIdentifier: String) -> Int? {
        switch modelIdentifier {
        case "MacBookPro18,1", "MacBookPro18,2":
            return 140
        default:
            return nil
        }
    }
}

