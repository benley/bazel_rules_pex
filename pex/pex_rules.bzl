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

### Setup

Add something like this to your WORKSPACE file:

    git_repository(
        name = "io_bazel_rules_pex",
        remote = "https://github.com/benley/bazel_rules_pex.git",
        tag = "0.1.6",
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
    if hasattr(dep.py, "transitive_egg_files"):
      transitive_eggs += dep.py.transitive_egg_files
  transitive_eggs += egg_file_types.filter(ctx.files.eggs)
  return transitive_eggs


def _collect_transitive_reqs(ctx):
  transitive_reqs = set(order="compile")
  for dep in ctx.attr.deps:
    if hasattr(dep.py, "transitive_reqs"):
      transitive_reqs += dep.py.transitive_reqs
  transitive_reqs += ctx.attr.reqs
  return transitive_reqs


def _collect_transitive_data(ctx):
  transitive_data = set(order="compile")
  for dep in ctx.attr.deps:
    if hasattr(dep.py, "transitive_data_files"):
      transitive_data += dep.py.transitive_data_files
  transitive_data += ctx.files.data
  return transitive_data


def _collect_transitive(ctx):
  return struct(
      transitive_sources = _collect_transitive_sources(ctx),
      transitive_egg_files = _collect_transitive_eggs(ctx),
      transitive_reqs = _collect_transitive_reqs(ctx),
      transitive_data_files = _collect_transitive_data(ctx),
  )


def _pex_library_impl(ctx):
  return struct(
      files = set(),
      py = _collect_transitive(ctx),
  )


def _textify_pex_input(input_map):
  """Converts map to text format. Each file on separate line."""
  kv_pairs = ['\t%s:%s' % (pkg, input_map[pkg]) for pkg in input_map.keys()]
  return '\n'.join(kv_pairs)


def _write_pex_manifest_text(modules, prebuilt_libs, resources, requirements):
  return '\n'.join(
      ['modules:\n%s' % _textify_pex_input(modules),
       'requirements:\n%s' % _textify_pex_input(dict(zip(requirements,requirements))),
       'resources:\n%s' % _textify_pex_input(resources),
       'nativeLibraries:\n',
       'prebuiltLibraries:\n%s' % _textify_pex_input(prebuilt_libs)
      ])


def _make_manifest(ctx, output):
  py = _collect_transitive(ctx)
  pex_modules = {}
  pex_prebuilt_libs = {}
  pex_resources = {}
  pex_requirements = []
  for f in py.transitive_sources:
    pex_modules[f.short_path] = f.path

  for f in py.transitive_egg_files:
    pex_prebuilt_libs[f.path] = f.path

  for f in py.transitive_data_files:
    pex_resources[f.short_path] = f.path

  manifest_text = _write_pex_manifest_text(pex_modules,
                                           pex_prebuilt_libs,
                                           pex_resources,
                                           py.transitive_reqs)
  ctx.file_action(
      output = output,
      content = manifest_text)


def _common_pex_arguments(entry_point, deploy_pex_path, manifest_file_path):
  return ['--entry-point', entry_point, deploy_pex_path, manifest_file_path]


def _pex_binary_impl(ctx):
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

  deploy_pex = ctx.new_file(
      ctx.configuration.bin_dir, ctx.outputs.executable, '.pex')

  manifest_file = ctx.new_file(
      ctx.configuration.bin_dir, deploy_pex, '.manifest')
  _make_manifest(ctx, manifest_file)

  py = _collect_transitive(ctx)

  pexbuilder = ctx.executable._pexbuilder

  # form the arguments to pex builder
  arguments =  [] if ctx.attr.zip_safe else ["--not-zip-safe"]
  arguments += [] if ctx.attr.pex_use_wheels else ["--no-use-wheel"]
  arguments += ["--python", ctx.attr.interpreter]
  # Put pex's caches in the bazel execroot so `bazel clean` is effective at
  # expunging those too.
  arguments += ["--pex-root", ".pex"]
  arguments += _common_pex_arguments(main_pkg,
                                     deploy_pex.path,
                                     manifest_file.path)

  # form the inputs to pex builder
  _inputs = (
      [manifest_file] +
      list(py.transitive_sources) +
      list(py.transitive_egg_files) +
      list(py.transitive_data_files) +
      list(ctx.attr._pexbuilder.data_runfiles.files) +
      [ctx.file._setuptools, ctx.file._wheel]
  )
  if main_file:
    _inputs.append(main_file)

  ctx.action(
      mnemonic = "PexPython",
      inputs = _inputs,
      outputs = [deploy_pex],
      executable = pexbuilder,
      execution_requirements = {
          "requires-network": "1",
      },
      env = {
          'PEX_VERBOSE': str(ctx.attr.pex_verbosity),
          'SETUPTOOLS_PATH': ctx.file._setuptools.path,
          'WHEEL_PATH': ctx.file._wheel.path,
      },
      arguments = arguments)

  # TODO(benley): what's the point of the separate deploy pex if it's just a
  #               duplicate of the executable?
  executable = ctx.outputs.executable
  ctx.action(
      inputs = [deploy_pex],
      outputs = [executable],
      command = "cp %s %s" % (deploy_pex.path, executable.path))

  # TODO(benley): is there any reason to generate/include transitive runfiles?
  return struct(files = set([executable]),
                #runfiles = ctx.runfiles(transitive_files = set(_inputs))
                )


def _pex_pytest_impl(ctx):
  # FIXME(benley): This may break on paths with spaces.
  #                But you should also stop wanting that.
  test_runner = ctx.executable.runner
  test_files = set(ctx.files.srcs)
  test_run_args = " ".join([
      ctx.attr.pytest_args,
      cmd_helper.join_paths(" ", test_files)
  ])

  executable = ctx.outputs.executable
  ctx.file_action(
      output = executable,
      content = "\n".join([
          "#!/bin/sh",
          "PYTHONDONTWRITEBYTECODE=1 %s %s\n" % (test_runner.short_path,
                                                 test_run_args),
      ])
  )

  _inputs = test_files + [test_runner]

  return struct(
      files = set([executable]),
      runfiles = ctx.runfiles(
          transitive_files = set(_inputs),
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
                            cfg = DATA_CFG),

    # From here down are used internally by pex_binary and pex_*test rules,
    # not pex_library.
    "_pexbuilder": attr.label(
        default = Label("//third_party/py/pex:pex_wrapper"),
        allow_files = False,
        executable = True
    ),
    "_wheel": attr.label(
        default = Label("@wheel_whl//file"),
        single_file = True,
    ),
    "_setuptools": attr.label(
        default = Label("@setuptools_whl//file"),
        single_file = True,
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
    "interpreter": attr.string(default="python2.7"),
    "pex_use_wheels": attr.bool(default=True),
    "pex_verbosity": attr.int(default=1),
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
        ),
        "pytest_args": attr.string(),
    }),
)


def pex_pytest(name, srcs, deps=[], pytest_args="", **kwargs):
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

    pytest_args: Extra commandline arguments for py.test.
  """
  if "main" in kwargs:
    fail("Specifying a `main` file makes no sense for pytest_pex_test.")
  if "entrypoint" in kwargs:
    fail("Do not specify `entrypoint` for pytest_pex_test.")

  pex_binary(
      name = "%s_runner" % name,
      srcs = srcs,
      deps = deps + ["//third_party/py/pytest"],
      entrypoint = "pytest",
      **kwargs
  )
  _pytest_pex_test(
      name = name,
      runner = ":%s_runner" % name,
      srcs = srcs,
      pytest_args = pytest_args,
  )


def pex_repositories():
  """Rules to be invoked from WORKSPACE for remote dependencies."""
  native.http_file(
      name = 'pytest_whl',
      url = 'https://pypi.python.org/packages/24/05/b6eaf80746a2819327207825e3dd207a93d02a9f63e01ce48562c143ed82/pytest-2.9.2-py2.py3-none-any.whl',
      sha256 = 'ccc23b4aab3ef3e19e731de9baca73f3b1a7e610d9ec65b28c36a5a3305f0349'
  )

  native.bind(
      name = "wheel/pytest",
      actual = "@pytest_whl//file",
  )

  native.http_file(
      name = 'py_whl',
      url = 'https://pypi.python.org/packages/19/f2/4b71181a49a4673a12c8f5075b8744c5feb0ed9eba352dd22512d2c04d47/py-1.4.31-py2.py3-none-any.whl',
      sha256 = '4a3e4f3000c123835ac39cab5ccc510642153bc47bc1f13e2bbb53039540ae69'
  )

  native.bind(
      name = "wheel/py",
      actual = "@py_whl//file",
  )

  native.http_file(
      name = "wheel_whl",
      url = "https://pypi.python.org/packages/a9/67/43036e2db1a344ad24ba468b6262826b3837ce629b7b4c09c18d3e2b5800/wheel-0.23.0-py2.py3-none-any.whl",
      sha256 = "cbc6b2e274557b5e8ee8b61ca4c0c781702956a80cdbeb7ec0446834b5078082",
  )

  native.http_file(
      name = "setuptools_whl",
      url = "https://pypi.python.org/packages/00/d5/1233f051f7ce669a2009301aa75f1efbd97ccde6b60236997fd9111d5297/setuptools-18.0.1-py2.py3-none-any.whl",
      sha256 = "825814864707c12e3eb7878c9d9cc7189507022d53476b71ef833b3d28df0c9c",
  )
