# Copyright 2014 Google Inc. All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Originally derived from:
# https://github.com/twitter/heron/blob/master/tools/rules/pex_rules.bzl

"""Python pex rules for Bazel

[![Build Status](https://travis-ci.org/benley/bazel_rules_pex.svg?branch=master)](https://travis-ci.org/benley/bazel_rules_pex)

### Setup

Add something like this to your WORKSPACE file:

    git_repository(
        name = "io_bazel_rules_pex",
        remote = "https://github.com/benley/bazel_rules_pex.git",
        tag = "0.3.0",
    )
    load("@io_bazel_rules_pex//pex:pex_rules.bzl", "pex_repositories")
    pex_repositories()

In a BUILD file where you want to use these rules, or in your
`tools/build_rules/prelude_bazel` file if you want them present repo-wide, add:

    load(
        "@io_bazel_rules_pex//pex:pex_rules.bzl",
        "pex_binary",
        "pex_library",
        "pex_test",
        "pex_pytest",
    )

Lastly, make sure that `tools/build_rules/BUILD` exists, even if it is empty,
so that Bazel can find your `prelude_bazel` file.
"""

pex_file_types = FileType([".py"])
egg_file_types = FileType([".egg", ".whl"])

# As much as I think this test file naming convention is a good thing, it's
# probably a bad idea to impose it as a policy to all OSS users of these rules,
# so I guess let's skip it.
#
# pex_test_file_types = FileType(["_unittest.py", "_test.py"])


def _collect_transitive_sources(ctx):
  source_files = set(order="compile")
  for dep in ctx.attr.deps:
    source_files += dep.py.transitive_sources
  source_files += pex_file_types.filter(ctx.files.srcs)
  return source_files


def _collect_transitive_eggs(ctx):
  transitive_eggs = set(order="compile")
  for dep in ctx.attr.deps:
    if hasattr(dep.py, "transitive_eggs"):
      transitive_eggs += dep.py.transitive_eggs
  transitive_eggs += egg_file_types.filter(ctx.files.eggs)
  return transitive_eggs


def _collect_transitive_reqs(ctx):
  transitive_reqs = set(order="compile")
  for dep in ctx.attr.deps:
    if hasattr(dep.py, "transitive_reqs"):
      transitive_reqs += dep.py.transitive_reqs
  transitive_reqs += ctx.attr.reqs
  return transitive_reqs


def _collect_transitive(ctx):
  return struct(
      # These rules don't use transitive_sources internally; it's just here for
      # parity with the native py_library rule type.
      transitive_sources = _collect_transitive_sources(ctx),
      transitive_eggs = _collect_transitive_eggs(ctx),
      transitive_reqs = _collect_transitive_reqs(ctx),
      # uses_shared_libraries = ... # native py_library has this. What is it?
  )


def _pex_library_impl(ctx):
  transitive_files = set(ctx.files.srcs)
  for dep in ctx.attr.deps:
    transitive_files += dep.default_runfiles.files
  return struct(
      files = set(),
      py = _collect_transitive(ctx),
      runfiles = ctx.runfiles(
          collect_default = True,
          transitive_files = set(transitive_files),
      )
  )


def _strip_import_paths_from_workspace_name(ctx, import_paths=[]):
  new_import_paths = set()
  workspace_name = ctx.workspace_name

  for import_path in import_paths:
    if import_path.startswith(workspace_name):
      new_import_paths += [import_path[len(workspace_name) + 1:]] # including /

  return new_import_paths


def _gen_manifest(py, runfiles, import_paths=[]):
  """Generate a manifest for pex_wrapper.

  Returns:
      struct(
          modules = [struct(src = "path_on_disk", dest = "path_in_pex"), ...],
          requirements = ["pypi_package", ...],
          prebuiltLibraries = ["path_on_disk", ...],
      )
  """

  pex_files = []

  for f in runfiles.files:
    dpath = f.short_path
    if dpath.startswith("../"):
      dpath = dpath[3:]

    for import_path in import_paths:
      if dpath.startswith(import_path):
          dpath = dpath[len(import_path) + 1:] # including /
          break # don't do multiple replaces

    pex_files.append(
        struct(
            src = f.path,
            dest = dpath,
        ),
    )

  return struct(
      modules = pex_files,
      requirements = list(py.transitive_reqs),
      prebuiltLibraries = [f.path for f in py.transitive_eggs],
  )


def _pex_binary_impl(ctx):
  transitive_files = set(ctx.files.srcs)

  if ctx.attr.entrypoint and ctx.file.main:
    fail("Please specify either entrypoint or main, not both.")
  if ctx.attr.entrypoint:
    main_file = None
    main_pkg = ctx.attr.entrypoint
  elif ctx.file.main:
    main_file = ctx.file.main
  else:
    main_file = pex_file_types.filter(ctx.files.srcs)[0]
  if main_file:
    # Translate main_file's short path into a python module name
    main_pkg = main_file.short_path.replace('/', '.')[:-3]
    transitive_files += [main_file]

  deploy_pex = ctx.new_file(
      ctx.configuration.bin_dir, ctx.outputs.executable, '.pex')

  py = _collect_transitive(ctx)

  import_paths = set()

  for dep in ctx.attr.deps:
    transitive_files += dep.default_runfiles.files
    for runfile in dep.default_runfiles.files:
      import_paths += dep.py.imports

  runfiles = ctx.runfiles(
      collect_default = True,
      transitive_files = transitive_files,
  )

  manifest_file = ctx.new_file(
      ctx.configuration.bin_dir, deploy_pex, '_manifest')

  manifest = _gen_manifest(
      py,
      runfiles,
      _strip_import_paths_from_workspace_name(ctx, import_paths))

  ctx.file_action(
      output = manifest_file,
      content = manifest.to_json(),
  )

  pexbuilder = ctx.executable._pexbuilder

  # form the arguments to pex builder
  arguments =  [] if ctx.attr.zip_safe else ["--not-zip-safe"]
  arguments += [] if ctx.attr.pex_use_wheels else ["--no-use-wheel"]
  if ctx.attr.interpreter:
    arguments += ["--python", ctx.attr.interpreter]
  for egg in py.transitive_eggs:
    arguments += ["--find-links", egg.dirname]
  arguments += [
      "--pex-root", ".pex",  # May be redundant since we also set PEX_ROOT
      "--entry-point", main_pkg,
      "--output-file", deploy_pex.path,
      "--cache-dir", ".pex/build",
      manifest_file.path,
  ]

  # form the inputs to pex builder
  _inputs = (
      [manifest_file] +
      list(runfiles.files) +
      list(py.transitive_eggs)
  )

  ctx.action(
      mnemonic = "PexPython",
      inputs = _inputs,
      outputs = [deploy_pex],
      executable = pexbuilder,
      execution_requirements = {
          "requires-network": "1",
      },
      env = {
          # TODO(benley): Write a repository rule to pick up certain
          # PEX-related environment variables (like PEX_VERBOSE) from the
          # system.
          # Also, what if python is actually in /opt or something?
          'PATH': '/bin:/usr/bin:/usr/local/bin',
          'PEX_VERBOSE': str(ctx.attr.pex_verbosity),
          'PEX_ROOT': '.pex',  # So pex doesn't try to unpack into $HOME/.pex
      },
      arguments = arguments,
  )

  executable = ctx.outputs.executable

  # There isn't much point in having both foo.pex and foo as identical pex
  # files, but someone is probably relying on that behaviour by now so we might
  # as well keep doing it.
  ctx.action(
      mnemonic = "LinkPex",
      inputs = [deploy_pex],
      outputs = [executable],
      command = "ln -f {pex} {exe} 2>/dev/null || cp -f {pex} {exe}".format(
          pex = deploy_pex.path,
          exe = executable.path,
      ),
  )

  return struct(
      files = set([executable]),  # Which files show up in cmdline output
      runfiles = runfiles,
  )


def _get_runfile_path(ctx, f):
  """Return the path to f, relative to runfiles."""
  if ctx.workspace_name:
    return ctx.workspace_name + "/" + f.short_path
  else:
    return f.short_path


def _pex_pytest_impl(ctx):
  test_runner = ctx.executable.runner
  output_file = ctx.outputs.executable

  test_file_paths = ["${RUNFILES}/" + _get_runfile_path(ctx, f) for f in ctx.files.srcs]
  ctx.template_action(
      template = ctx.file.launcher_template,
      output = output_file,
      substitutions = {
          "%test_runner%": _get_runfile_path(ctx, test_runner),
          "%test_files%": " \\\n    ".join(test_file_paths),
      },
      executable = True,
  )

  transitive_files = set(ctx.files.srcs + [test_runner])
  for dep in ctx.attr.deps:
    transitive_files += dep.default_runfiles

  return struct(
      runfiles = ctx.runfiles(
          files = [output_file],
          transitive_files = transitive_files,
          collect_default = True
      )
  )


pex_attrs = {
    "srcs": attr.label_list(flags = ["DIRECT_COMPILE_TIME_INPUT"],
                            allow_files = pex_file_types),
    "deps": attr.label_list(allow_files = False,
                            providers = ["py"]),
    "eggs": attr.label_list(flags = ["DIRECT_COMPILE_TIME_INPUT"],
                            allow_files = egg_file_types),
    "reqs": attr.string_list(),
    "data": attr.label_list(allow_files = True,
                            cfg = "data"),

    # Used by pex_binary and pex_*test, not pex_library:
    "_pexbuilder": attr.label(
        default = Label("//pex:pex_wrapper"),
        executable = True,
        cfg = "host",
    ),
}


def _dmerge(a, b):
  """Merge two dictionaries, a+b

  Workaround for https://github.com/bazelbuild/skydoc/issues/10
  """
  return dict(a.items() + b.items())


pex_bin_attrs = _dmerge(pex_attrs, {
    "main": attr.label(allow_files = True,
                       single_file = True),
    "entrypoint": attr.string(),
    "interpreter": attr.string(),
    "pex_use_wheels": attr.bool(default=True),
    "pex_verbosity": attr.int(default=0),
    "zip_safe": attr.bool(
        default = True,
        mandatory = False,
    ),
})

pex_library = rule(
    _pex_library_impl,
    attrs = pex_attrs
)

pex_binary_outputs = {
    "deploy_pex": "%{name}.pex"
}

pex_binary = rule(
    _pex_binary_impl,
    executable = True,
    attrs = pex_bin_attrs,
    outputs = pex_binary_outputs,
)
"""Build a deployable pex executable.

Args:
  deps: Python module dependencies.

    `pex_library` and `py_library` rules should work here.

  eggs: `.egg` and `.whl` files to include as python packages.

  reqs: External requirements to retrieve from pypi, in `requirements.txt` format.

    This feature will reduce build determinism!  It tells pex to resolve all
    the transitive python dependencies and fetch them from pypi.

    It is recommended that you use `eggs` instead where possible.

  data: Files to include as resources in the final pex binary.

    Putting other rules here will cause the *outputs* of those rules to be
    embedded in this one. Files will be included as-is. Paths in the archive
    will be relative to the workspace root.

  main: File to use as the entrypoint.

    If unspecified, the first file from the `srcs` attribute will be used.

  entrypoint: Name of a python module to use as the entrypoint.

    e.g. `your.project.main`

    If unspecified, the `main` attribute will be used.
    It is an error to specify both main and entrypoint.

  interpreter: Path to the python interpreter the pex should to use in its shebang line.
"""

pex_test = rule(
    _pex_binary_impl,
    executable = True,
    attrs = pex_bin_attrs,
    outputs = pex_binary_outputs,
    test = True,
)

_pytest_pex_test = rule(
    _pex_pytest_impl,
    executable = True,
    test = True,
    attrs = _dmerge(pex_attrs, {
        "runner": attr.label(
            executable = True,
            mandatory = True,
            cfg = "data",
        ),
        "launcher_template": attr.label(
            allow_files = True,
            single_file = True,
            default = Label("//pex:testlauncher.sh.template"),
        ),
    }),
)


def pex_pytest(name, srcs, deps=[], eggs=[], data=[],
               args=[],
               flaky=False,
               local=None,
               size=None,
               timeout=None,
               tags=[],
               **kwargs):
  """A variant of pex_test that uses py.test to run one or more sets of tests.

  This produces two things:

    1. A pex_binary (`<name>_runner`) containing all your code and its
       dependencies, plus py.test, and the entrypoint set to the py.test
       runner.
    2. A small shell script to launch the `<name>_runner` executable with each
       of the `srcs` enumerated as commandline arguments.  This is the actual
       test entrypoint for bazel.

  Almost all of the attributes that can be used with pex_test work identically
  here, including those not specifically mentioned in this docstring.
  Exceptions are `main` and `entrypoint`, which cannot be used with this macro.

  Args:

    srcs: List of files containing tests that should be run.
  """
  if "main" in kwargs:
    fail("Specifying a `main` file makes no sense for pex_pytest.")
  if "entrypoint" in kwargs:
    fail("Do not specify `entrypoint` for pex_pytest.")

  pex_binary(
      name = "%s_runner" % name,
      srcs = srcs,
      deps = deps,
      data = data,
      eggs = eggs + [
          "@pytest_whl//file",
          "@py_whl//file",
      ],
      entrypoint = "pytest",
      testonly = True,
      **kwargs
  )
  _pytest_pex_test(
      name = name,
      runner = ":%s_runner" % name,
      args = args,
      data = data,
      flaky = flaky,
      local = local,
      size = size,
      srcs = srcs,
      timeout = timeout,
      tags = tags,
  )


def pex_repositories():
  """Rules to be invoked from WORKSPACE for remote dependencies."""
  native.http_file(
      name = 'pytest_whl',
      url = 'https://pypi.python.org/packages/c4/bf/80d1cd053b1c86f6ecb23300fba3a7c572419b5edc155da0f3f104d42775/pytest-3.0.2-py2.py3-none-any.whl',
      sha256 = '4b0872d00159dd8d7a27c4a45a2be77aac8a6e70c3af9a7c76c040c3e3715b9d'
  )

  native.http_file(
      name = 'py_whl',
      url = 'https://pypi.python.org/packages/19/f2/4b71181a49a4673a12c8f5075b8744c5feb0ed9eba352dd22512d2c04d47/py-1.4.31-py2.py3-none-any.whl',
      sha256 = '4a3e4f3000c123835ac39cab5ccc510642153bc47bc1f13e2bbb53039540ae69'
  )

  native.http_file(
      name = "wheel_src",
      url = "https://pypi.python.org/packages/c9/1d/bd19e691fd4cfe908c76c429fe6e4436c9e83583c4414b54f6c85471954a/wheel-0.29.0.tar.gz",
      sha256 = "1ebb8ad7e26b448e9caa4773d2357849bf80ff9e313964bcaf79cbf0201a1648",
  )

  native.http_file(
      name = "setuptools_src",
      url = "https://pypi.python.org/packages/d3/16/21cf5dc6974280197e42d57bf7d372380562ec69aef9bb796b5e2dbbed6e/setuptools-20.10.1.tar.gz",
      sha256 = "3e59c885f09ed0d631816468e431b347b5103339e77a21cbf56df6283319b5dd",
  )

  native.http_file(
      name = "pex_src",
      url = "https://pypi.python.org/packages/6d/b9/aacedca314f7061f84c021c9eaac9ceac9c57f277e4e9bbb6d998facec8d/pex-1.1.14.tar.gz",
      sha256 = "2d0f5ec39d61c0ef0f806247d7e2702e5354583df7f232db5d9a3b287173e857",
  )

  native.http_file(
      name = "requests_src",
      url = "https://pypi.python.org/packages/2e/ad/e627446492cc374c284e82381215dcd9a0a87c4f6e90e9789afefe6da0ad/requests-2.11.1.tar.gz",
      sha256 = "5acf980358283faba0b897c73959cecf8b841205bb4b2ad3ef545f46eae1a133",
  )

  native.new_http_archive(
      name = "virtualenv",
      url = "https://pypi.python.org/packages/5c/79/5dae7494b9f5ed061cff9a8ab8d6e1f02db352f3facf907d9eb614fb80e9/virtualenv-15.0.2.tar.gz",
      sha256 = "fab40f32d9ad298fba04a260f3073505a16d52539a84843cf8c8369d4fd17167",
      strip_prefix = "virtualenv-15.0.2",
      build_file_content = "\n".join([
          "py_binary(",
          "    name = 'virtualenv',",
          "    srcs = ['virtualenv.py'],",
          "    data = glob(['**/*']),",
          "    visibility = ['//visibility:public'],",
          ")",
      ])
  )
