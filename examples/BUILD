load("//pex:pex_rules.bzl", "pex_binary", "pex_library", "pex_pytest")

pex_binary(
    name = "foo",
    srcs = ["foo.py"],
)

pex_library(
    name = "libfoo",
    srcs = ["foo.py"],
    reqs = [
        "flask",
        "pyyaml",
    ],
)

pex_pytest(
    name = "foo_test",
    size = "small",
    srcs = ["foo_test.py"],
    args = ["--strict"],
    deps = [":libfoo"],
)
