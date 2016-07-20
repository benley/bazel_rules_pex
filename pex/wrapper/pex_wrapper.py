#!/usr/bin/env python2.7
""" Pex builder wrapper """

import pex.bin.pex as pexbin
from pex.common import safe_delete
from pex.tracer import TRACER
from pex.variables import ENV

import os
import sys


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


def main():
    pparser, resolver_options_builder = pexbin.configure_clp()
    poptions, args = pparser.parse_args(sys.argv)

    manifest_file = args[1]
    manifest_text = open(manifest_file, 'r').read()

    if poptions.pex_root:
        ENV.set('PEX_ROOT', poptions.pex_root)
    else:
        poptions.pex_root = ENV.PEX_ROOT

    if poptions.cache_dir:
        poptions.cache_dir = pexbin.make_relative_to_root(poptions.cache_dir)
    poptions.interpreter_cache_dir = pexbin.make_relative_to_root(poptions.interpreter_cache_dir)

    if manifest_text.startswith('"') and manifest_text.endswith('"'):
        manifest_text = manifest_text[1:len(manifest_text) - 1]

    manifest = parse_manifest(manifest_text)

    reqs = manifest.get('requirements', {}).keys()

    with ENV.patch(PEX_VERBOSE=str(poptions.verbosity)):
        with TRACER.timed('Building pex'):
            pex_builder = pexbin.build_pex(reqs, poptions,
                                           resolver_options_builder)

        # Add source files from the manifest
        for dst, src in manifest.get('modules', {}).items():
            # NOTE(agallagher): calls the `add_source` and `add_resource` below
            # hard-link the given source into the PEX temp dir.  Since OS X and
            # Linux behave different when hard-linking a source that is a
            # symbolic link (Linux does *not* follow symlinks), resolve any
            # layers of symlinks here to get consistent behavior.
            try:
                pex_builder.add_source(dereference_symlinks(src), dst)
            except OSError as err:
                raise Exception("Failed to add %s: %s" % (src, err))

        # Add resources from the manifest
        for dst, src in manifest.get('resources', {}).items():
            pex_builder.add_resource(dereference_symlinks(src), dst)

        # Add eggs/wheels from the manifest
        for req in manifest.get('prebuiltLibraries', []):
            try:
                pex_builder.add_dist_location(req)
            except Exception as err:
                raise Exception("Failed to add %s: %s" % (req, err))

        # TODO(mikekap): Do something about manifest['nativeLibraries'].

        pexbin.log('Saving PEX file to %s' % poptions.pex_name,
                   v=poptions.verbosity)
        tmp_name = poptions.pex_name + '~'
        safe_delete(tmp_name)
        pex_builder.build(tmp_name)
        os.rename(tmp_name, poptions.pex_name)


if __name__ == '__main__':
    main()
