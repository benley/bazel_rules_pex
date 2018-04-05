load(
    "@io_bazel_skydoc//skylark:skylark.bzl",
    "skydoc_repositories",
    "skylark_library",
    "skylark_doc",
)

genrule(
    name = "README",
    srcs = [":docs"],
    outs = ["README.md"],
    cmd = "unzip -q $< && mv pex/pex_rules.md $@",
)

skylark_doc(
    name = "docs",
    srcs = ["//pex:pex_rules.bzl"],
    visibility = ["//visibility:public"],
)
