#!/bin/sh
set -e

bazel build //:README
cp -fv bazel-genfiles/README.md README.md
