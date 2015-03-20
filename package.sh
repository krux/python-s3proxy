#!/usr/bin/env bash
set -ex

### name of the package, project, etc
PACKAGE_NAME=${PACKAGE-'s3proxy'}

### set $DEST_DIR
DEST_DIR="/usr/local"

### set $PACKAGE_DIR
PACKAGE_DIR="/krux-${PACKAGE_NAME}"

PIP_VERSION=1.4.1

### set $TARGET
VIRT=.ci.virtualenv
TARGET=${VIRT}${PACKAGE_DIR}

### install virtualenv-tools
###
### XXX This will do the appropriate magic rewrites of the headers within the
###     the build virtualenv to that of the destination virtualenv.  It is NOT a
###     run-time requirement or dependency.
###
if which virtualenv-tools; then
    VENTOOLS="$(which virtualenv-tools)"
else
    ### install virtualenv-tools in its own virtualenv so we don't break it
    ### while running it below
    VENVTOOLS_VENV=".ci.virtualenv-tools"
    virtualenv --no-site-packages "${VENVTOOLS_VENV}"
    . "${VENVTOOLS_VENV}"/bin/activate
    pip install virtualenv-tools
    deactivate
    VENVTOOLS="$(pwd)/${VENVTOOLS_VENV}"/bin/virtualenv-tools
fi

### set up a virtualenv for this build and activate it
virtualenv --no-site-packages ${TARGET}
. ${TARGET}/bin/activate

### set up pip, install any requirements needed
pip install $PIP_OPTIONS pip==${PIP_VERSION}
pip install $PIP_OPTIONS -r requirements.pip

### install the application into the virtualenv
python setup.py install

### XXX test the application
#nosetests

### set $BUILD_NUMBER
BUILD_NUMBER=${BUILD_NUMBER-'development'}

### set $VERSION
VERSION=${VERSION-"$(python setup.py --version)-${BUILD_NUMBER}"}

### package version
PACKAGE_VERSION=${VERSION-$( date -u +%Y%m%d%H%M )}

### clean and update the virtualenv environment 
###
### XXX This actually performs the magic rewrite which was installed above such
###     that the headers are that of the destination filesystem.
###
cd ${TARGET}
"${VENVTOOLS}" --update-path ${DEST_DIR}${PACKAGE_DIR}
cd -

### delete *.pyc and *.pyo files
find ${VIRT} -iname *.pyo -o -iname *.pyc -delete

### link any entry points defined to /usr/local/bin
mkdir -p ${VIRT}/bin
cat <<EOF | python
from ConfigParser import RawConfigParser
import os
rcp = RawConfigParser()
rcp.read('s3proxy.egg-info/entry_points.txt')
os.chdir('${VIRT}/bin')
for item in rcp.items('console_scripts'):
    src = '..${PACKAGE_DIR}/bin/' + item[0]
    dest = item[0]
    print 'symlinking ' + src + ' to ' + dest
    if os.path.exists(dest):
        os.remove(dest)
    os.symlink(src, dest)
EOF

### create the package
fpm --verbose -s dir -t deb -n ${PACKAGE_NAME} --prefix ${DEST_DIR} -v ${VERSION} -C ${VIRT} .
