#!/usr/bin/env python2.7

import sys
import subprocess

def main():
    if len(sys.argv) != 2:
        sys.stderr.write('Error: Pass path to an interpreter pex\n')
        sys.exit(1)
    interpreter_pex_path = sys.argv[1]

    output = subprocess.check_output([interpreter_pex_path], stderr=subprocess.STDOUT)
    assert 'InteractiveConsole' in output
    print 'PASS'

if __name__ == '__main__':
    main()
