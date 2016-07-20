genrule(
    name = "README",
    srcs = [":docs"],
    outs = ["README.md"],
    cmd = "unzip -q $< && mv pex_rules.md $@",
)

skylark_doc(
    name = "docs",
    srcs = ["//pex:pex_rules.bzl"],
    visibility = ["//visibility:public"],
)

