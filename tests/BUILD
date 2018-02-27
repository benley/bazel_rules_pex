load(
    "@//pex:pex_rules.bzl",
    "pex_binary",
    "pex_library",
    "pex_test",
    "pex_pytest",
)

pex_pytest(
    name = "third_party_test",
    srcs = ["third_party_test.py"],
    deps = ["//third_party/example:example"],
)
