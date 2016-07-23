exports_files(["pex_rules.bzl"])

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

        PYTHON_VERSION="$$(python -c "import sys; print sys.version[:3]")"
        # Create /.../lib/pythonX.Y/site-packages so easy_install doesn't fail
        # `sed` works around https://github.com/pypa/setuptools/issues/672
        export PYTHONPATH="$$(python -m site --user-site | \
            sed "s|lib/python/site-packages|lib/python$$PYTHON_VERSION/site-packages|")/"
        mkdir -p $$PYTHONPATH

        # Bootstrap setuptools:
        tar xzf $(location @setuptools_src//file)
        (cd setuptools* && \
         python setup.py --quiet install --prefix=$$PYTHONUSERBASE)

        # Use that new setuptools to install wheel and pex:
        $$PYTHONUSERBASE/bin/easy_install --quiet \
                                          --build-directory $(@D)/build \
                                          --prefix=$$PYTHONUSERBASE \
                                          $(location @wheel_src//file)
        $$PYTHONUSERBASE/bin/easy_install --quiet \
                                          --build-directory $(@D)/build \
                                          --prefix=$$PYTHONUSERBASE \
                                          $(location @pex_src//file)

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
