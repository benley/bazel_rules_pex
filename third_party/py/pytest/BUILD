licenses(["notice"])

package(default_visibility = ["//visibility:public"])

load("//:pex_rules.bzl", "pex_library")

pex_library(
    name = "pytest",
    eggs = ["//external:wheel/pytest"],
    deps = ["//third_party/py/py"],
)
