#!/usr/bin/env python2.7

import subprocess
import sys

EXPECTED_OUTPUT = "I'm a pex file!\n"


def test_pex(pex_path, expected_interpreter):
    with open(pex_path) as f:
        interpreter_line = f.readline()
    if interpreter_line != expected_interpreter:
        sys.stderr.write('ERROR %s: Unexpected interpreter: %s\n' % (
            pex_path, repr(interpreter_line)))
        sys.stderr.write('    Expected: %s\n' % (repr(expected_interpreter)))
        sys.exit(1)

    # check that it can be executed
    output = subprocess.check_output(pex_path)
    assert output == EXPECTED_OUTPUT


def main():
    '''Tests that the pex_binary interpreter attribute works.'''

    if len(sys.argv) != 3:
        sys.stderr.write('Error: Pass path to default PEX and changed PEX\n')
        sys.exit(1)
    default_pex = sys.argv[1]
    changed_pex = sys.argv[2]

    test_pex(default_pex, '#!/usr/bin/env python2.7\n')
    test_pex(changed_pex, '#!/usr/bin/python2.7\n')
    print 'PASS'


if __name__ == '__main__':
    main()
