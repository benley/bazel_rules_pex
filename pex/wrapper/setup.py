"""Minimal setup.py for pex_wrapper"""

import setuptools

setuptools.setup(
    name="pex_wrapper",
    author="foo",
    author_email="bar",
    url="foo",
    py_modules=["pex_wrapper"],
    install_requires=[
        "pex",
        "wheel",
    ],
)
