load("//pex:pex_rules.bzl", "pex_library", "pex_pytest")

# targets in third_party sub-directories must have license by default see:
# https://github.com/bazelbuild/bazel/issues/188
pex_library(
    name = "example",
    srcs = ["example.py"],
    licenses = ["notice"],  # makes bazel's default --check-licenses happy
    visibility = ["//visibility:public"],
)

pex_pytest(
    name = "example_test",
    srcs = ["example_test.py"],
    licenses = ["notice"],  # makes bazel's default --check-licenses happy
    deps = [":example"],
)
