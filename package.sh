#!/usr/bin/env bash
set -ex

### name of the package, project, etc
PACKAGE_NAME=${PACKAGE-'s3proxy'}

### set $DEST_DIR
DEST_DIR="/usr/local"

### set $PACKAGE_DIR
PACKAGE_DIR="/krux/packages/${PACKAGE_NAME}"

PIP_VERSION=1.4.1

### set $TARGET
VIRT=.ci.virtualenv
TARGET=${VIRT}${PACKAGE_DIR}

### set up a virtualenv for this build and activate it
virtualenv --no-site-packages ${TARGET}
. ${TARGET}/bin/activate

### set up pip, install any requirements needed
pip install $PIP_INDEXES pip==${PIP_VERSION}
pip install $PIP_INDEXES -r requirements.pip

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

### install virtualenv-tools
###
### XXX This will do the appropriate magic rewrites of the headers within the
###     the build virtualenv to that of the destination virtualenv.  It is NOT a
###     run-time requirement or dependency.
###
pip install virtualenv-tools

### clean and update the virtualenv environment 
###
### XXX This actually performs the magic rewrite which was installed above such
###     that the headers are that of the destination filesystem.
###
cd ${TARGET}
virtualenv-tools --update-path ${DEST_DIR}${PACKAGE_DIR}
cd -

### delete *.pyc and *.pyo files
find ${VIRT} -iname *.pyo -o -iname *.pyc -delete

### create the package
fpm --verbose -s dir -t deb -n ${PACKAGE_NAME} --prefix ${DEST_DIR} -v ${VERSION} -C ${VIRT} .
