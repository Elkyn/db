{
  "targets": [
    {
      "target_name": "elkyn_store",
      "sources": [
        "src/elkyn_binding.cc"
      ],
      "include_dirs": [
        "../zig-out/include"
      ],
      "libraries": [
        "/Users/a664144/projects/elkyn-db/zig-out/lib/libelkyn-embedded-static.a",
        "-L/opt/homebrew/opt/lmdb/lib",
        "-llmdb"
      ],
      "cflags": [
        "-std=c++17"
      ],
      "cflags_cc": [
        "-std=c++17"
      ],
      "conditions": [
        [
          "OS=='mac'",
          {
            "xcode_settings": {
              "GCC_ENABLE_CPP_EXCEPTIONS": "YES",
              "CLANG_CXX_LIBRARY": "libc++",
              "MACOSX_DEPLOYMENT_TARGET": "10.15"
            }
          }
        ],
        [
          "OS=='linux'",
          {
            "cflags": [
              "-fexceptions"
            ],
            "cflags_cc": [
              "-fexceptions"
            ]
          }
        ]
      ]
    }
  ]
}