{
  "targets": [
    {
      "target_name": "elkyn_store",
      "sources": [
        "src/elkyn_binding.cc"
      ],
      "include_dirs": [
        "../../zig-out/include"
      ],
      "conditions": [
        [
          "OS=='mac'",
          {
            "libraries": [
              "../../zig-out/lib/libelkyn-embedded-static.a",
              "-llmdb"
            ],
            "include_dirs": [
              "/opt/homebrew/include",
              "/usr/local/include"
            ],
            "library_dirs": [
              "/opt/homebrew/lib",
              "/usr/local/lib"
            ],
            "xcode_settings": {
              "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
              "CLANG_CXX_LIBRARY": "libc++",
              "MACOSX_DEPLOYMENT_TARGET": "10.15",
              "OTHER_CPLUSPLUSFLAGS": ["-std=c++17"]
            }
          }
        ],
        [
          "OS=='linux'",
          {
            "libraries": [
              "../../zig-out/lib/libelkyn-embedded-static.a",
              "-llmdb"
            ],
            "cflags": [
              "-fexceptions",
              "-std=c++17"
            ],
            "cflags_cc": [
              "-fexceptions",
              "-std=c++17"
            ]
          }
        ]
      ]
    }
  ]
}