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

# Tests that the interpreter attribute works
pex_binary(
    name = "foo_interpreter",
    srcs = ["foo.py"],
    interpreter = "/usr/bin/python2.7",
)
sh_test(
    name = "interpreter_test",
    srcs = ["interpreter_test.py"],
    data = [":foo", ":foo_interpreter"],
    args = ["$(location :foo)", "$(location :foo_interpreter)"],
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
