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
