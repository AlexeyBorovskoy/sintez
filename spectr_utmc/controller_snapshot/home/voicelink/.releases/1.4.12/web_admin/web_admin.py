#!/usr/bin/env python2

import sys
import getopt
from version import __version__


if __name__ == '__main__':
    try:
        opts, args = getopt.getopt(sys.argv[1:], 'hv', ['help', 'version'])
    except getopt.error as msg:
        print(msg)
        print('Try "%s --help" for more information.' % sys.argv[0])
        sys.exit(2)

    outputs = []
    for opt, arg in opts:
        if opt in ('-h', '--help'):
            print('Usage: command [OPTION]')
            print('  -h, --help\t Display this help and exit')
            print('  -v, --version\t Output version information and exit')
            sys.exit(0)
        elif opt in ('-v', '--version'):
            print(__version__)
            sys.exit(0)