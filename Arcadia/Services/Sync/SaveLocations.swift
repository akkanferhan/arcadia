import Foundation

/// A folder of saves, save states or memory cards that an emulator reads and writes.
/// With iCloud sync on, the folder becomes a link into `Arcadia/Saves/<emulator>/<cloudPath>`.
struct SaveLocation: Equatable, Sendable {
    let emulatorID: String
    /// Where the emulator expects the folder.
    let local: URL
    /// Path inside the emulator's folder in iCloud Drive.
    let cloudPath: String
}

extension SaveLocation {
    /// Every save folder Arcadia controls. Emulators that keep saves inside a disk image (xemu)
    /// or next to the game (melonDS), or mixed with installed games (Azahar, Flycast), are left out:
    /// syncing those safely is not possible file by file.
    static func all(data: (String) -> URL = Paths.data,
                    applicationSupport: URL = Presets.applicationSupport) -> [SaveLocation] {
        func at(_ id: String, _ path: String, cloud: String) -> SaveLocation {
            SaveLocation(emulatorID: id, local: data(id).appendingPathComponent(path, isDirectory: true), cloudPath: cloud)
        }
        let ppsspp = "home/.config/ppsspp/PSP"
        let rpcs3 = "home/Library/Application Support/rpcs3"
        return [
            at("retroarch", "saves", cloud: "saves"),
            at("retroarch", "states", cloud: "states"),
            at("duckstation", "memcards", cloud: "memcards"),
            SaveLocation(emulatorID: "duckstation",
                         local: applicationSupport.appendingPathComponent("DuckStation/savestates", isDirectory: true),
                         cloudPath: "savestates"),
            at("ppsspp", "\(ppsspp)/SAVEDATA", cloud: "SAVEDATA"),
            at("ppsspp", "\(ppsspp)/PPSSPP_STATE", cloud: "PPSSPP_STATE"),
            at("dolphin", "GC", cloud: "GC"),
            at("dolphin", "Wii/title", cloud: "Wii/title"),
            at("dolphin", "StateSaves", cloud: "StateSaves"),
            at("cemu", "mlc01/usr/save", cloud: "save"),
            at("rpcs3", "\(rpcs3)/dev_hdd0/home/00000001/savedata", cloud: "savedata"),
            at("rpcs3", "\(rpcs3)/savestates", cloud: "savestates"),
            // Current shadPS4 keeps saves in user/home/<user>/savedata, older builds in user/savedata.
            at("shadps4", "user/home", cloud: "home"),
            at("shadps4", "user/savedata", cloud: "savedata"),
        ]
    }
}
