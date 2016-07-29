exports_files(["pex_rules.bzl"])

# Can't use pex_binary to build this one, so we have this elaborate ritual:
genrule(
    name = "pex_wrapper",
    srcs = [
        "wrapper/setup.py",
        "wrapper/pex_wrapper.py",
        "wrapper/README",
        "@setuptools_src//file",
        "@wheel_src//file",
        "@pex_src//file",
        "@requests_src//file",
    ],
    tools = ["@virtualenv//:virtualenv"],
    outs = ["pex_wrapper.pex"],
    executable = True,
    output_to_bindir = True,
    message = "Bootstrapping pex",
    cmd = """
        OUTDIR=$$(cd $(@D) && pwd)
        # Workaround really long shebang lines breaking on linux:
        # Use a /tmp path, but keep the actual venv inside the bazel outdir.
        # Avoids having to worry about cleanup, even if sandboxing is off.
        TMPF=$$(mktemp)
        ln -sf "$$OUTDIR" "$$TMPF"
        VENV="$${TMPF}/venv"

        $(location @virtualenv//:virtualenv) --no-download --quiet "$$VENV"
        PYTHON="$$VENV/bin/python"

        $$VENV/bin/pip install pex \
            --quiet --no-cache-dir --no-index --build $(@D)/pexbuild \
            --find-links $$(dirname $(location @pex_src//file)) \
            --find-links $$(dirname $(location @setuptools_src//file))

        # Work around setuptools insistance on writing to the source directory,
        # which is discouraged by Bazel (and annoying)
        cp -r $$(dirname $(location wrapper/setup.py)) $(@D)/.pex_wrapper
        ( cd $(@D)/.pex_wrapper
          $$PYTHON setup.py --quiet sdist --dist-dir $$OUTDIR )

        # Use the bootstrapped pex to build pex_wrapper.pex
        $$VENV/bin/pex pex_wrapper \
            --disable-cache --no-index -m pex_wrapper -o $@ \
            --find-links $$OUTDIR \
            --find-links $$(dirname $(location @pex_src//file)) \
            --find-links $$(dirname $(location @setuptools_src//file)) \
            --find-links $$(dirname $(location @requests_src//file)) \
            --find-links $$(dirname $(location @wheel_src//file))
    """,
    visibility = ["//visibility:public"],
)
