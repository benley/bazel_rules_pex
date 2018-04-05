load(
    "@//pex:pex_rules.bzl",
    "pex_binary",
    "pex_library",
    "pex_test",
    "pex_pytest",
)

# targets in third_party sub-directories must have license by default see:
# https://github.com/bazelbuild/bazel/issues/188
pex_library(
    name = "example",
    srcs = ["example.py"],
    visibility = ["//visibility:public"],
    licenses = ["notice"],  # makes bazel's default --check-licenses happy
)

pex_pytest(
    name = "example_test",
    srcs = ["example_test.py"],
    deps = [":example"],
    licenses = ["notice"],  # makes bazel's default --check-licenses happy
)
