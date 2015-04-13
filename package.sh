#!/usr/bin/env bash
set -ex

PYTHON_PACKAGE_NAME="$(python setup.py --name)"
DEFAULT_PACKAGE_NAME="python-${PYTHON_PACKAGE_NAME}"
PACKAGE_NAME="${PACKAGE-$DEFAULT_PACKAGE_NAME}"

DEST_DIR="/usr/local"
PACKAGE_DIR="/krux-${PACKAGE_NAME}"

PIP_VERSION="1.4.1"

BUILD_DIR=".build"
TARGET="${BUILD_DIR}${PACKAGE_DIR}"

if [ -e "${BUILD_DIR}" ]; then
    rm -rf "${BUILD_DIR}"
fi

# install virtualenv-tools
#
# XXX This will do the appropriate magic rewrites of the headers within the
#     the build virtualenv to that of the destination virtualenv.  It is NOT a
#     run-time requirement or dependency.
#
# XXX use the system installed virtualenv-tools if it exists
if which virtualenv-tools; then
    VENTOOLS="$(which virtualenv-tools)"
else
    # install virtualenv-tools in its own virtualenv so we don't break it
    # while running it below
    VENVTOOLS_VENV=".tools"
    VENVTOOLS="$(pwd)/${VENVTOOLS_VENV}/bin/virtualenv-tools"
    if [ ! -e "${VENVTOOLS}" ]; then
        if [ -e "${VENVTOOLS_VENV}" ]; then
            rm -rf "${VENVTOOLS_VENV}"
        fi
        virtualenv --no-site-packages "${VENVTOOLS_VENV}"
        source "${VENVTOOLS_VENV}/bin/activate"
        pip install virtualenv-tools
        deactivate
    fi
fi

# set up a virtualenv for this build and activate it
virtualenv --no-site-packages "${TARGET}"
source "${TARGET}/bin/activate"

# set up pip, install any requirements needed
pip install $PIP_OPTIONS "pip==${PIP_VERSION}"
pip install $PIP_OPTIONS -r requirements.pip -I

# install the application into the virtualenv
python setup.py install

# XXX test the application
#nosetests

BUILD_NUMBER="${BUILD_NUMBER-development}"

DEFAULT_VERSION="$(python setup.py --version)-${BUILD_NUMBER}"
VERSION="${VERSION-${DEFAULT_VERSION}}"

# clean and update the virtualenv environment 
#
# XXX This does the magic needed to make the virtualenv work
# from $DEST_DIR, which is where the package will install it.
#
cd "${TARGET}"
"${VENVTOOLS}" --update-path "${DEST_DIR}${PACKAGE_DIR}"
cd -

# delete *.pyc and *.pyo files
find "${BUILD_DIR}" -iname *.pyo -o -iname *.pyc -delete

# link any entry points defined to /usr/local/bin
mkdir -p "${BUILD_DIR}/bin"
cat <<EOF | python
from ConfigParser import RawConfigParser
import os
import sys

rcp = RawConfigParser()
egg = '${PYTHON_PACKAGE_NAME}.egg-info'
entry_points = os.path.join(egg, 'entry_points.txt')
if not os.path.exists(egg) or not os.path.exists(entry_points):
    sys.exit(0)
rcp.read(entry_points)
if 'console_scripts' not in rcp.sections():
    sys.exit(0)
os.chdir('${BUILD_DIR}/bin')
for item in rcp.items('console_scripts'):
    src = '..${PACKAGE_DIR}/bin/' + item[0]
    dest = item[0]
    print 'symlinking ' + src + ' to ' + dest
    if os.path.exists(dest):
        os.remove(dest)
    os.symlink(src, dest)
EOF

# create the package
fpm --verbose -s dir -t deb -n "${PACKAGE_NAME}" --prefix "${DEST_DIR}" -v "${VERSION}" -C "${BUILD_DIR}" .
