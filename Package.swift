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
        .library(name: "SwiftLlama", targets: ["SwiftLlama"]),
        .library(name: "whisper_cpp", targets: ["whisper_cpp"]),
        .library(name: "ggml_metal", targets: ["ggml_metal"]),
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
        .target(name: "SwiftLlama", dependencies: [
            .target(name: "whisper_cpp"),
        ]),
        .target(name: "LibWhisper", dependencies: [
            .target(name: "whisper_cpp"),
            .product(name: "SDL", package: "SwiftSDL2"),
        ]),
        .target(
            name: "ggml_metal",
            dependencies: ["whisper_cpp"],
            exclude: [
//                "Resources/metal/ggml-metal_dadbed9.metal",
                "Resources/metal/ggml-metal_from-llmfarm.metal",
            ],
            resources: [
//                .process("ggml-metal.metal"),
//                .copy("Resources/tokenizers"),
                .copy("Resources/metal")
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-Ofast"]), //comment this if you need to Debug llama_cpp
                .unsafeFlags(["-DGGML_METAL_NDEBUG"]),
                .unsafeFlags(["-DGGML_USE_K_QUANTS"]),
//                .unsafeFlags(["-DSWIFT_PACKAGE"]),
//                .unsafeFlags(["-w"]),    // ignore all warnings
                //                .unsafeFlags(["-DGGML_QKK_64"]), // Dont forget to comment this if you dont use QKK_64
                
//                .unsafeFlags(["-Wno-shorten-64-to-32"]),
                .define("GGML_USE_ACCELERATE", .when(platforms: [.macOS, .macCatalyst, .iOS])),
                .define("GGML_USE_METAL", .when(platforms: [.macOS, .macCatalyst, .iOS])),
                .unsafeFlags(["-DNDEBUG"]),
                .unsafeFlags(["-pthread"]),
                .unsafeFlags(["-fno-objc-arc"]),
//            ]),
            ]
//            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .target(
            name: "whisper_cpp",
            dependencies: [
                .product(name: "SDL", package: "SwiftSDL2"),
            ], 
//            exclude: [
//                "Resources/metal/ggml-metal_dadbed9.metal",
//                "Resources/metal/ggml-metal_from-llmfarm.metal",
//            ],
            resources: [
//                .process("ggml-metal.metal"),
                .copy("Resources/tokenizers"),
//                .copy("Resources/metal")
            ],
            publicHeadersPath: "include",
            cxxSettings: [
                .unsafeFlags(["-Ofast"]), //comment this if you need to Debug llama_cpp
//                .unsafeFlags(["-O3"]),
                .unsafeFlags(["-mfma","-mfma","-mavx","-mavx2","-mf16c","-msse3","-mssse3"]), //for Intel CPU
                .unsafeFlags(["-DGGML_METAL_NDEBUG"]),
                .unsafeFlags(["-DGGML_USE_K_QUANTS"]),
                .unsafeFlags(["-DSWIFT_PACKAGE"]),
                .unsafeFlags(["-w"]),    // ignore all warnings
                //                .unsafeFlags(["-DGGML_QKK_64"]), // Dont forget to comment this if you dont use QKK_64
                
                .unsafeFlags(["-Wno-shorten-64-to-32"]),
                .define("GGML_USE_ACCELERATE", .when(platforms: [.macOS, .macCatalyst, .iOS])),
                .define("GGML_USE_METAL", .when(platforms: [.macOS, .macCatalyst, .iOS])),
                .unsafeFlags(["-DNDEBUG"]),
                .unsafeFlags(["-pthread"]),
                .unsafeFlags(["-fno-objc-arc"]),
            ],
            swiftSettings: [.interoperabilityMode(.Cxx)])
    ],
    cxxLanguageStandard: CXXLanguageStandard.cxx20)
