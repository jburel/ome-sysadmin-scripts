#!/bin/bash

set -eux

BASE_DIR=build
RPMS_DIR=$BASE_DIR/RPMS/x86_64
DEBUG_DIR=$BASE_DIR/DEBUG
SRPMS_DIR=$BASE_DIR/SRPMS

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
	mock -r ome-6-x86_64 rebuild $PACKAGE-*.src.rpm $@
	popd

	mv /var/lib/mock/ome-6-x86_64/result/$PACKAGE-*.src.rpm $SRPMS_DIR
	mv /var/lib/mock/ome-6-x86_64/result/$PACKAGE-debuginfo-*.rpm $DEBUG_DIR
	mv /var/lib/mock/ome-6-x86_64/result/$PACKAGE-*.rpm $RPMS_DIR
}

if [ ! -f /etc/mock/ome-6-x86_64.cfg ]; then
	echo "Missing mock config: /etc/mock/ome-6-x86_64.cfg"
	echo "Download from https://github.com/manics/centos-rpms/blob/master/mock-configs/ome-6-x86_64.cfg"
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

