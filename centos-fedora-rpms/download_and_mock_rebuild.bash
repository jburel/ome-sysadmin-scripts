#!/bin/bash

set -eux

BASE_DIR=build
RPMS_DIR=$BASE_DIR/RPMS/x86_64
DEBUG_DIR=$BASE_DIR/DEBUG
SRPMS_DIR=$BASE_DIR/SRPMS
MOCK_CFG=ome-6-x86_64

download_and_build() {
	PACKAGE=$1
	shift

	echo **************************************************
	echo Building $PACKAGE with options $@
	echo **************************************************

	rm -rf $PACKAGE
	mkdir $PACKAGE
	pushd $PACKAGE
	yumdownloader -c ../yum.conf --disablerepo=\* --enablerepo=fedora\* \
		--source $PACKAGE
	mock -r $MOCK_CFG rebuild $PACKAGE-*.src.rpm $@
	popd

	mv /var/lib/mock/$MOCK_CFG/result/$PACKAGE-*.src.rpm $SRPMS_DIR
	mv /var/lib/mock/$MOCK_CFG/result/$PACKAGE-debuginfo-*.rpm $DEBUG_DIR
	mv /var/lib/mock/$MOCK_CFG/result/$PACKAGE-*.rpm $RPMS_DIR
}

if [ ! -f /etc/mock/$MOCK_CFG.cfg ]; then
	echo "Missing mock config: /etc/mock/$MOCK_CFG.cfg"
	echo "Maybe download from https://github.com/manics/centos-rpms/blob/master/mock-configs/"
	exit 1
fi

rm -rf $BASE_DIR
mkdir -p $RPMS_DIR
mkdir -p $DEBUG_DIR
mkdir -p $SRPMS_DIR

download_and_build boost --without python3 --without mpich
download_and_build cmake
download_and_build git

createrepo $RPMS_DIR

