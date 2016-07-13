genrule(
    name = "README",
    srcs = ["//pex:docs"],
    outs = ["README.md"],
    cmd = "unzip -q $< && mv pex_rules.md $@",
)
