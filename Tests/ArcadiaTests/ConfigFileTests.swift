import Foundation
import Testing
@testable import Arcadia

@Suite struct INIFileTests {
    @Test func updatesExistingKeysAndKeepsTheRest() throws {
        let folder = TemporaryFolder()
        let file = folder.write("a.ini", text: "; comment\ntop=1\n\n[Main]\nA = 1\nB = 2\n\n[GPU]\nX = y\n")
        try INIFile.update(file) { ini in
            ini.set("A", "9", section: "Main")
            ini.set("C", "3", section: "Main")
            ini.set("top", "2")
            ini.set("X", "Metal", section: "GPU")
        }
        #expect(folder.read("a.ini") == "; comment\ntop = 2\n\n[Main]\nA = 9\nB = 2\nC = 3\n\n[GPU]\nX = Metal\n")
    }

    @Test func createsMissingFileAndSection() throws {
        let folder = TemporaryFolder()
        let file = folder.url.appendingPathComponent("new/config.ini")
        try INIFile.update(file, separator: "=") { $0.set("fullscreen", "true", section: "UI") }
        #expect(folder.read("new/config.ini") == "[UI]\nfullscreen=true\n")
    }

    @Test func replaceSectionWritesRepeatedKeys() throws {
        let folder = TemporaryFolder()
        let file = folder.write("pad.ini", text: "[Pad1]\nCross = Keyboard/K\nOld = 1\n\n[Hotkeys]\nA = B\n")
        try INIFile.update(file) { ini in
            ini.replaceSection("Pad1", with: [("Cross", "Keyboard/K"), ("Cross", "SDL-0/A")])
        }
        #expect(folder.read("pad.ini") == "[Pad1]\nCross = Keyboard/K\nCross = SDL-0/A\n\n[Hotkeys]\nA = B\n")
    }
}

@Suite struct YAMLFileTests {
    @Test func setsNestedKeysAndCreatesMissingOnes() throws {
        let folder = TemporaryFolder()
        let file = folder.write("config.yml", text: "Core:\n  PPU Decoder: Interpreter\nVideo:\n  Renderer: OpenGL\n  Vulkan:\n    Adapter: \"\"\nAudio:\n  Renderer: Null\n")
        try YAMLFile.update(file) { yaml in
            yaml.set(["Video", "Renderer"], "Vulkan")
            yaml.set(["Video", "Vulkan", "Asynchronous Texture Streaming 2"], "true")
            yaml.set(["Video", "Resolution Scale"], "200")
            yaml.set(["Miscellaneous", "Exit RPCS3 when process finishes"], "true")
        }
        #expect(folder.read("config.yml") == """
        Core:
          PPU Decoder: Interpreter
        Video:
          Renderer: Vulkan
          Vulkan:
            Adapter: ""
            Asynchronous Texture Streaming 2: true
          Resolution Scale: 200
        Audio:
          Renderer: Null
        Miscellaneous:
          Exit RPCS3 when process finishes: true

        """)
    }

    @Test func doesNotConfuseSameKeyInAnotherSection() throws {
        let folder = TemporaryFolder()
        let file = folder.write("c.yml", text: "Video:\n  Renderer: OpenGL\nAudio:\n  Renderer: Null\n")
        try YAMLFile.update(file) { $0.set(["Audio", "Renderer"], "Cubeb") }
        #expect(folder.read("c.yml") == "Video:\n  Renderer: OpenGL\nAudio:\n  Renderer: Cubeb\n")
    }
}

@Suite struct StructuredSettingsTests {
    @Test func xmlUpdatesNestedElements() throws {
        let folder = TemporaryFolder()
        let file = folder.url.appendingPathComponent("settings.xml")
        try XMLSettings.update(file, root: "content", [("fullscreen", "true"), ("Graphic/api", "1")])
        try XMLSettings.update(file, root: "content", [("Graphic/api", "2")])
        let document = try XMLDocument(contentsOf: file)
        #expect(try document.nodes(forXPath: "/content/fullscreen").first?.stringValue == "true")
        #expect(try document.nodes(forXPath: "/content/Graphic/api").first?.stringValue == "2")
    }

    @Test func jsonMergesWithoutDroppingUnknownKeys() throws {
        let folder = TemporaryFolder()
        let file = folder.write("config.json", text: #"{"GPU":{"other":1},"Keep":true}"#)
        try JSONSettings.update(file, [(["GPU", "full_screen"], true), (["Log", "enable"], false)])
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let gpu = try #require(json["GPU"] as? [String: Any])
        #expect(gpu["full_screen"] as? Bool == true)
        #expect(gpu["other"] as? Int == 1)
        #expect(json["Keep"] as? Bool == true)
        #expect((json["Log"] as? [String: Any])?["enable"] as? Bool == false)
    }
}
