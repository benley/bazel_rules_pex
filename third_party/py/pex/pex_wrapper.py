#!/usr/bin/env python2.7
""" Pex builder wrapper for use with pex_rules.bzl

Derived from https://github.com/twitter/heron/blob/master/3rdparty/pex/_pex.py
"""

import distutils.spawn
import functools
import optparse
import os
import sys
import tempfile
import zipfile

WHEEL_PATH = os.getenv("WHEEL_PATH")
SETUPTOOLS_PATH = os.getenv("SETUPTOOLS_PATH")
sys.path.insert(0, WHEEL_PATH)
sys.path.insert(0, SETUPTOOLS_PATH)

PKG_RESOURCES_PATH = 'third_party/setuptools/pkg_resources.py'

# Try to detect if we're running from source via the repo.  Add appropriate
# deps to our python path, so we can find the twitter libs and
# setuptools at runtime.  Also, locate the `pkg_resources` modules
# via our local setuptools import.
if not zipfile.is_zipfile(sys.argv[0]):
    sys.modules.pop('twitter', None)
    sys.modules.pop('twitter.common', None)
    sys.modules.pop('twitter.common.python', None)

    BAZEL_ROOT = os.sep.join(__file__.split(os.sep)[:-4])
    sys.path.insert(0, os.path.join(BAZEL_ROOT, 'third_party/py/pex'))
    sys.path.insert(0, os.path.join(BAZEL_ROOT, 'third_party/setuptools'))

    PKG_RESOURCES_PATH = os.path.join(BAZEL_ROOT, PKG_RESOURCES_PATH)

# Otherwise we're probably running from a PEX, so use pkg_resources to extract
# itself from the binary.
else:
    import pkg_resources
    pkg_resources_py_tmp = tempfile.NamedTemporaryFile(
        prefix='pkg_resources.py')
    pkg_resources_py_tmp.write(
        pkg_resources.resource_string(__name__, PKG_RESOURCES_PATH))
    pkg_resources_py_tmp.flush()
    PKG_RESOURCES_PATH = pkg_resources_py_tmp.name

    sys.path.insert(0, os.path.dirname(__file__))

from pex.bin.pex import (build_pex, configure_clp, resolve_interpreter,
                         CANNOT_SETUP_INTERPRETER)
from pex.common import die
from pex.interpreter import PythonInterpreter
from pex.version import SETUPTOOLS_REQUIREMENT, WHEEL_REQUIREMENT


def dereference_symlinks(src):
    """
    Resolve all symbolic references that `src` points to.  Note that this
    is different than `os.path.realpath` as path components leading up to
    the final location may still be symbolic links.
    """
    while os.path.islink(src):
        src = os.path.join(os.path.dirname(src), os.readlink(src))

    return src


def parse_manifest(manifest_text):
    """ Parse a pex manifest.

    Manifest format:

        modules:
        	key:value
        	...
        resources:
        	key:value
        	...
        nativeLibraries:
        	key:value
        	...
        prebuiltLibraries:
        	key:value
        	...

    Indents are *tabs*.  Sections may be left blank.
    """
    lines = manifest_text.split('\n')
    manifest = {}
    curr_key = ''
    for line in lines:
        tokens = line.split(':')
        if len(tokens) != 2:
            continue
        elif not line.startswith('\t'):
            manifest[tokens[0]] = {}
            curr_key = tokens[0]
        else:
            # line is of form <tab>key:value
            manifest[curr_key][tokens[0][1:]] = tokens[1]
    return manifest


def resolve_or_die(interpreter, requirement, options):
    """ Find a compatible interpreter, or give up and abort. """
    resolve = functools.partial(resolve_interpreter,
                                options.interpreter_cache_dir,
                                options.repos)

    interpreter = resolve(interpreter, requirement)
    if interpreter is None:
        die('Could not find compatible interpreter that meets requirement %s' %
            requirement, CANNOT_SETUP_INTERPRETER)
    return interpreter


def main():
    """ Main """
    # Options that this wrapper will accept from the bazel rule
    parser = optparse.OptionParser(usage="usage: %prog [options] output")
    parser.add_option('--entry-point', default='__main__')
    parser.add_option('--no-pypi', action='store_false',
                      dest='pypi', default=True)
    parser.add_option('--not-zip-safe', action='store_false',
                      dest='zip_safe', default=True)
    parser.add_option('--python', default="python2.7")
    parser.add_option('--find-links', dest='find_links', default='')
    parser.add_option('--no-use-wheel', action='store_false',
                      dest='use_wheel', default=True)
    parser.add_option('--pex-root', dest='pex_root', default=".pex")
    options, args = parser.parse_args()

    # The manifest is passed via stdin or a file, as it can sometimes get too
    # large to be passed as a CLA.
    if len(args) == 2:
        output = args[0]
        manifest_text = open(args[1], 'r').read()
    elif len(args) == 1:
        output = args[0]
        manifest_text = sys.stdin.read()
    else:
        parser.error("'output' positional argument is required")
        return 1

    if manifest_text.startswith('"') and manifest_text.endswith('"'):
        manifest_text = manifest_text[1:len(manifest_text) - 1]

    manifest = parse_manifest(manifest_text)

    # These are the options that pex will use
    pparser, resolver_options_builder = configure_clp()

    poptions, preqs = pparser.parse_args(sys.argv)
    poptions.entry_point = options.entry_point
    poptions.find_links = options.find_links
    poptions.pypi = options.pypi
    poptions.python = options.python
    poptions.use_wheel = options.use_wheel
    poptions.zip_safe = options.zip_safe

    poptions.pex_root = options.pex_root
    poptions.cache_dir = options.pex_root + "/build"
    poptions.interpreter_cache_dir = options.pex_root + "/interpreters"

    # sys.stderr.write("pex options: %s\n" % poptions)
    os.environ["PATH"] = os.getenv("PATH",
                                   "%s:/bin:/usr/bin" % poptions.python)

    if os.path.exists(options.python):
        pybin = poptions.python
    else:
        pybin = distutils.spawn.find_executable(options.python)

    # The version of pkg_resources.py (from setuptools) on some distros is
    # too old for PEX. So we keep a recent version in and force it into the
    # process by constructing a custom PythonInterpreter instance using it.
    # interpreter = PythonInterpreter.from_binary(pybin,
    #                                             [SETUPTOOLS_PATH,
    #                                              WHEEL_PATH])
    interpreter = PythonInterpreter(
        pybin,
        PythonInterpreter.from_binary(pybin).identity,
        extras={
            # TODO: Fix this to resolve automatically
            ('setuptools', '18.0.1'): SETUPTOOLS_PATH,
            # FIXME: I don't think this accomplishes anything at all.
            ('wheel', '0.23.0'): WHEEL_PATH,
        })

    # resolve setuptools
    interpreter = resolve_or_die(interpreter,
                                 SETUPTOOLS_REQUIREMENT,
                                 poptions)

    # possibly resolve wheel
    if interpreter and poptions.use_wheel:
        interpreter = resolve_or_die(interpreter,
                                     WHEEL_REQUIREMENT,
                                     poptions)

    # Add prebuilt libraries listed in the manifest.
    reqs = manifest.get('requirements', {}).keys()
    # if len(reqs) > 0:
    #   sys.stderr.write("pex requirements: %s" % reqs)
    pex_builder = build_pex(reqs, poptions,
                            resolver_options_builder,
                            interpreter=interpreter)

    # Set whether this PEX is zip-safe, meaning everything will stay zipped
    # up and we'll rely on python's zip-import mechanism to load modules
    # from the PEX.  This may not work in some situations (e.g. native
    # libraries, libraries that want to find resources via the FS).
    pex_builder.info.zip_safe = options.zip_safe

    # Set the starting point for this PEX.
    pex_builder.info.entry_point = options.entry_point

    pex_builder.add_source(
        dereference_symlinks(PKG_RESOURCES_PATH),
        os.path.join(pex_builder.BOOTSTRAP_DIR, 'pkg_resources.py'))

    # Add the sources listed in the manifest.
    for dst, src in manifest['modules'].iteritems():
        # NOTE(agallagher): calls the `add_source` and `add_resource` below
        # hard-link the given source into the PEX temp dir.  Since OS X and
        # Linux behave different when hard-linking a source that is a
        # symbolic link (Linux does *not* follow symlinks), resolve any
        # layers of symlinks here to get consistent behavior.
        try:
            pex_builder.add_source(dereference_symlinks(src), dst)
        except OSError as err:
            raise Exception("Failed to add {}: {}".format(src, err))

    # Add resources listed in the manifest.
    for dst, src in manifest['resources'].iteritems():
        # NOTE(agallagher): see rationale above.
        pex_builder.add_resource(dereference_symlinks(src), dst)

    # Add prebuilt libraries listed in the manifest.
    for req in manifest.get('prebuiltLibraries', []):
        try:
            pex_builder.add_dist_location(req)
        except Exception as err:
            raise Exception("Failed to add {}: {}".format(req, err))

    # TODO(mikekap): Do something about manifest['nativeLibraries'].

    # Generate the PEX file.
    pex_builder.build(output)


sys.exit(main())
