skylark_doc(
    name = "docs",
    srcs = ["pex_rules.bzl"],
    visibility = ["//visibility:public"],
)

# Can't use pex_binary to build this one, so we have this elaborate ritual:
genrule(
    name = "pex_wrapper",
    srcs = [
        "wrapper/setup.py",
        "wrapper/pex_wrapper.py",
        "@setuptools_src//file",
        "@wheel_src//file",
        "@pex_src//file",
    ],
    outs = ["pex_wrapper.pex"],
    executable = True,
    cmd = """
        OUTDIR=$$(cd $(@D) && pwd)
        export PYTHONUSERBASE=$$OUTDIR/__pythonuserbase

        # FIXME(benley): get rid of this hardcoded python2.7 reference
        # (why the heck is this necessary?)
        mkdir -p $$PYTHONUSERBASE/lib/python2.7/site-packages

        # Bootstrap setuptools:
        tar xzf $(location @setuptools_src//file)
        (cd setuptools* && python setup.py install --user)

        # Use that new setuptools to install wheel and pex:
        $$PYTHONUSERBASE/bin/easy_install --user $(location @wheel_src//file)
        $$PYTHONUSERBASE/bin/easy_install --user $(location @pex_src//file)

        (
         cd $$(dirname $(location wrapper/setup.py))
         python setup.py bdist_egg
        )
        # Use pex to build a pex of itself:
        $$PYTHONUSERBASE/bin/pex $$(dirname $(location wrapper/setup.py))/dist/pex_wrapper-*.egg \
            --disable-cache --no-index -m pex_wrapper -o $@ \
            --find-links $$(dirname $(location @pex_src//file)) \
            --find-links $$(dirname $(location @setuptools_src//file)) \
            --find-links $$(dirname $(location @wheel_src//file))
    """,
    visibility = ["//visibility:public"],
)
