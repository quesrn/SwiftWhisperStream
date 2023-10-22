// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SwiftWhisperStream",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v13),
    ],
    products: [
        .library(name: "SwiftWhisperStream", targets: ["SwiftWhisperStream"]),
    ],
    dependencies: [
        .package(url: "https://github.com/lake-of-fire/SwiftSDL2.git", branch: "master"),
        .package(url: "https://github.com/TeHikuMedia/libfvad-ios.git", branch: "tumu"),
    ],
    targets: [
        .target(
            name: "SwiftWhisperStream",
            dependencies: [
                .product(name: "libfvad", package: "libfvad-ios"),
                .target(name: "whisper_cpp"),
                .target(name: "LibWhisper"),
            ]),
        .target(name: "LibWhisper", dependencies: [
            .target(name: "whisper_cpp"),
        ]),
        .target(
            name: "whisper_cpp",
            dependencies: [
                .product(name: "SDL", package: "SwiftSDL2"),
            ], 
//            exclude: [
//                "ggml-metal.metal",
//            ],
            resources: [
                .process("ggml-metal.metal"),
            ],
            publicHeadersPath: "include",
            cSettings: [
                .unsafeFlags(["-Wno-shorten-64-to-32"]),
                .define("GGML_USE_ACCELERATE", .when(platforms: [.macOS, .macCatalyst, .iOS])),
                .define("GGML_USE_METAL", .when(platforms: [.macOS, .macCatalyst, .iOS])),
                .unsafeFlags(["-O3"]),
                .unsafeFlags(["-DNDEBUG"]),
                .unsafeFlags(["-pthread"]),
                .unsafeFlags(["-fno-objc-arc"]),
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("Accelerate"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("MetalPerformanceShaders"),
            ]),
//            ),
//        .testTarget(name: "WhisperTests", dependencies: [.target(name: "SwiftWhisper")], resources: [.copy("TestResources/")])
    ],
    cxxLanguageStandard: CXXLanguageStandard.cxx20
)
