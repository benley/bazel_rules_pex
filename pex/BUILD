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

        # Create /.../lib/pythonX.Y/site-packages so easy_install doesn't fail
        mkdir -p $$(python -m site --user-site)

        # Bootstrap setuptools:
        tar xzf $(location @setuptools_src//file)
        (cd setuptools* && python setup.py --quiet install --user)

        # Use that new setuptools to install wheel and pex:
        $$PYTHONUSERBASE/bin/easy_install --quiet \
                                          --build-directory $(@D)/build \
                                          --user $(location @wheel_src//file)
        $$PYTHONUSERBASE/bin/easy_install --quiet \
                                          --build-directory $(@D)/build \
                                          --user $(location @pex_src//file)

        # Work around setuptools insistance on writing to the source directory,
        # which is discouraged by Bazel (and annoying)
        cp -r $$(dirname $(location wrapper/setup.py)) $(@D)/.pex_wrapper
        ( cd $(@D)/.pex_wrapper
          python setup.py --quiet sdist --dist-dir $$OUTDIR )

        # Use the bootstrapped pex to build pex_wrapper.pex
        $$PYTHONUSERBASE/bin/pex pex_wrapper \
            --disable-cache --no-index -m pex_wrapper -o $@ \
            --find-links $$OUTDIR \
            --find-links $$(dirname $(location @pex_src//file)) \
            --find-links $$(dirname $(location @setuptools_src//file)) \
            --find-links $$(dirname $(location @wheel_src//file))
    """,
    visibility = ["//visibility:public"],
)
