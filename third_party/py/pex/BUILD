licenses(["notice"])

package(default_visibility = ["//visibility:public"])

load("//:pex_rules.bzl", "pex_binary", "pex_library")

py_binary(
    name = "pex_wrapper",
    srcs = ["pex_wrapper.py"],
    deps = [":_pex_lib_native"],
)

py_library(
    name = "_pex_lib_native",
    srcs = glob(["**/*.py"]),
    data = glob([
        "*.whl",
        "*.egg",
    ]),
    deps = ["//third_party/setuptools:pkg_resources"],
)

pex_binary(
    name = "pex",
    srcs = ["pex_wrapper.py"],
    main = "pex_wrapper.py",
    deps = [":_pex_lib_pex"],
)

pex_library(
    name = "_pex_lib_pex",
    srcs = glob(["**/*.py"]),
    eggs = glob([
        "*.whl",
        "*.egg",
    ]),
    deps = ["//third_party/setuptools:pkg_resources"],
)
