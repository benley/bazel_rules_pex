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

# Derived from https://github.com/twitter/heron/blob/master/tools/rules/pex_rules.bzl

pex_file_types = FileType([".py"])
egg_file_types = FileType([".egg", ".whl"])
pex_test_file_types = FileType(["_unittest.py", "_test.py"])


def collect_transitive_sources(ctx):
  source_files = set(order="compile")
  for dep in ctx.attr.deps + ctx.attr._extradeps:
    source_files += dep.py.transitive_sources
  source_files += pex_file_types.filter(ctx.files.srcs)
  return source_files


def collect_transitive_eggs(ctx):
  transitive_eggs = set(order="compile")
  for dep in ctx.attr.deps + ctx.attr._extradeps:
    if hasattr(dep.py, "transitive_egg_files"):
      transitive_eggs += dep.py.transitive_egg_files
  transitive_eggs += egg_file_types.filter(ctx.files.eggs)
  return transitive_eggs


def collect_transitive_reqs(ctx):
  transitive_reqs = set(order="compile")
  for dep in ctx.attr.deps + ctx.attr._extradeps:
    if hasattr(dep.py, "transitive_reqs"):
      transitive_reqs += dep.py.transitive_reqs
  transitive_reqs += ctx.attr.reqs
  return transitive_reqs


def collect_transitive_data(ctx):
  transitive_data = set(order="compile")
  for dep in ctx.attr.deps + ctx.attr._extradeps:
    if hasattr(dep.py, "transitive_data_files"):
      transitive_data += dep.py.transitive_data_files
  transitive_data += ctx.files.data
  return transitive_data


def pex_library_impl(ctx):
  transitive_sources = collect_transitive_sources(ctx)
  transitive_eggs = collect_transitive_eggs(ctx)
  transitive_reqs = collect_transitive_reqs(ctx)
  transitive_data = collect_transitive_data(ctx)
  return struct(
      files = set(),
      py = struct(
          transitive_sources = transitive_sources,
          transitive_reqs = transitive_reqs,
          transitive_egg_files = transitive_eggs,
          transitive_data_files = transitive_data,
      ))


# Converts map to text format. Each file on separate line.
def textify_pex_input(input_map):
  kv_pairs = ['\t%s:%s' % (pkg, input_map[pkg]) for pkg in input_map.keys()]
  return '\n'.join(kv_pairs)


def write_pex_manifest_text(modules, prebuilt_libs, resources, requirements):
  return '\n'.join(
      ['modules:\n%s' % textify_pex_input(modules),
       'requirements:\n%s' % textify_pex_input(dict(zip(requirements,requirements))),
       'resources:\n%s' % textify_pex_input(resources),
       'nativeLibraries:\n',
       'prebuiltLibraries:\n%s' % textify_pex_input(prebuilt_libs)
      ])


def make_manifest(ctx, output):
  transitive_sources = collect_transitive_sources(ctx)
  transitive_reqs = collect_transitive_reqs(ctx)
  transitive_eggs = collect_transitive_eggs(ctx)
  transitive_data = collect_transitive_data(ctx)
  pex_modules = {}
  pex_prebuilt_libs = {}
  pex_resources = {}
  pex_requirements = []
  for f in transitive_sources:
    pex_modules[f.short_path] = f.path

  for f in transitive_eggs:
    pex_prebuilt_libs[f.path] = f.path

  for f in transitive_data:
    pex_resources[f.short_path] = f.path

  manifest_text = write_pex_manifest_text(pex_modules,
                                          pex_prebuilt_libs,
                                          pex_resources,
                                          transitive_reqs)
  ctx.file_action(
      output = output,
      content = manifest_text)


def common_pex_arguments(entry_point, deploy_pex_path, manifest_file_path):
  return ['--entry-point', entry_point, deploy_pex_path, manifest_file_path]


def pex_binary_impl(ctx):
  if not ctx.file.main:
    main_file = pex_file_types.filter(ctx.files.srcs)[0]
  else:
    main_file = ctx.file.main

  # Package name is same as folder name followed by filename (without .py extension)
  main_pkg = main_file.path.replace('/', '.')[:-3]

  deploy_pex = ctx.new_file(
      ctx.configuration.bin_dir, ctx.outputs.executable, '.pex')

  manifest_file = ctx.new_file(
      ctx.configuration.bin_dir, deploy_pex, '.manifest')
  make_manifest(ctx, manifest_file)

  transitive_sources = collect_transitive_sources(ctx)
  transitive_eggs = collect_transitive_eggs(ctx)
  transitive_data = collect_transitive_data(ctx)
  pexbuilder = ctx.executable._pexbuilder

  # form the arguments to pex builder
  arguments =  [] if ctx.attr.zip_safe else ["--not-zip-safe"]
  arguments += [] if ctx.attr.pex_use_wheels else ["--no-use-wheel"]
  arguments += common_pex_arguments(main_pkg,
                                    deploy_pex.path,
                                    manifest_file.path)

  # form the inputs to pex builder
  _inputs = (
      [main_file, manifest_file] +
      list(transitive_sources) +
      list(transitive_eggs) +
      list(transitive_data) +
      list(ctx.attr._pexbuilder.data_runfiles.files))

  ctx.action(
      mnemonic = "PexPython",
      inputs = _inputs,
      outputs = [deploy_pex],
      executable = pexbuilder,
      arguments = arguments)

  executable = ctx.outputs.executable
  ctx.action(
      inputs = [deploy_pex],
      outputs = [executable],
      command = "cp %s %s" % (deploy_pex.path, executable.path))

  # TODO(bstaffin): is there any real benefit from including all the
  # transitive runfiles?
  return struct(files = set([executable]))#,
                #runfiles = ctx.runfiles(transitive_files = set(_inputs)))


def pex_pytest_impl(ctx):
  deploy_pex = ctx.new_file(
      ctx.configuration.bin_dir, ctx.outputs.executable, '.pex')

  manifest_file = ctx.new_file(
      ctx.configuration.bin_dir, deploy_pex, '.manifest')
  make_manifest(ctx, manifest_file)

  # Get pex test files
  transitive_sources = collect_transitive_sources(ctx)
  transitive_eggs = collect_transitive_eggs(ctx)
  transitive_resources = ctx.files.data
  pexbuilder = ctx.executable._pexbuilder

  pex_test_files = pex_file_types.filter(ctx.files.srcs)
  # FIXME(bstaffin): This will probably break on paths with spaces
  #                  But you should also stop wanting that.
  test_run_args = ' '.join([f.path for f in pex_test_files])

  _inputs = (
      [manifest_file] +
      list(transitive_sources) +
      list(transitive_eggs) +
      list(transitive_resources) +
      list(ctx.attr._pexbuilder.data_runfiles.files)
  )
  ctx.action(
      inputs = _inputs,
      executable = pexbuilder,
      outputs = [ deploy_pex ],
      mnemonic = "PexPython",
      arguments = common_pex_arguments('pytest',
                                       deploy_pex.path,
                                       manifest_file.path))

  executable = ctx.outputs.executable
  ctx.file_action(
      output = executable,
      content = ('PYTHONDONTWRITEBYTECODE=1 %s %s\n\n' %
                 (deploy_pex.short_path, test_run_args)))

  return struct(
      files = set([executable]),
      runfiles = ctx.runfiles(
          transitive_files = set(_inputs + [deploy_pex]),
          collect_default = True
      ),
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
    "main": attr.label(allow_files = True,
                       single_file = True),
    "pex_use_wheels": attr.bool(default=True),
    "_extradeps": attr.label_list(providers = ["py"],
                                  allow_files = False),
}

pex_bin_attrs = pex_attrs + {
    "zip_safe": attr.bool(
        default = True,
        mandatory = False,
    ),
    "_pexbuilder": attr.label(
        default = Label("//third_party/py/pex:pex_wrapper"),
        allow_files = False,
        executable = True,
    )
}

pex_library = rule(
    pex_library_impl,
    attrs = pex_attrs
)

pex_binary_outputs = {
    "deploy_pex": "%{name}.pex"
}

pex_binary = rule(
    pex_binary_impl,
    executable = True,
    attrs = pex_bin_attrs,
    outputs = pex_binary_outputs,
)

pex_test = rule(
    pex_binary_impl,
    executable = True,
    attrs = pex_bin_attrs,
    outputs = pex_binary_outputs,
    test = True,
)

pytest_pex_test = rule(
    pex_pytest_impl,
    executable = True,
    attrs = pex_attrs + {
        "_pexbuilder": attr.label(
            default = Label("//third_party/py/pex:pex_wrapper"),
            allow_files = False,
            executable = True,
        ),
        '_extradeps': attr.label_list(
            default = [
                Label('//third_party/py/pytest')
            ],
        ),
    },
    test = True,
)
