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
    srcs = ["foo_test.py"],
    args = ["--strict"],
    deps = [":libfoo"],
    size = "small",
)

# Tests that building a pex without entry points is supported
pex_binary(
    name = "interpreter_only",
)
sh_test(
    name = "interpreter_only_test",
    srcs = ["interpreter_only_test.py"],
    data = [":interpreter_only"],
    args = ["$(location :interpreter_only)"],
)
