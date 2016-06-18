workspace(name = "io_bazel_rules_pex")

http_file(
    name = 'pytest_whl',
    url = 'https://pypi.python.org/packages/24/05/b6eaf80746a2819327207825e3dd207a93d02a9f63e01ce48562c143ed82/pytest-2.9.2-py2.py3-none-any.whl',
    sha256 = 'ccc23b4aab3ef3e19e731de9baca73f3b1a7e610d9ec65b28c36a5a3305f0349'
)

bind(
    name = "wheel/pytest",
    actual = "@pytest_whl//file",
)
http_file(
    name = 'py_whl',
    url = 'https://pypi.python.org/packages/19/f2/4b71181a49a4673a12c8f5075b8744c5feb0ed9eba352dd22512d2c04d47/py-1.4.31-py2.py3-none-any.whl',
    sha256 = '4a3e4f3000c123835ac39cab5ccc510642153bc47bc1f13e2bbb53039540ae69'
)

bind(
    name = "wheel/py",
    actual = "@py_whl//file",
)
