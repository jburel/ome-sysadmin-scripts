#!/bin/sh

set -eu

ICE_BASEDIR=${ICE_BASEDIR:-$HOME/ice}

failed()
{
	echo "FAILED: $1"
	exit 1
}

test_ice_version()
{
	echo Checking $1 $2
	eval $($ICE_BASEDIR/ice-multi-config.sh $1) || \
		failed "Setting ice version"

	echo ICE_HOME=$ICE_HOME
	echo PYTHONPATH=$PYTHONPATH
	echo PATH=$PATH
	echo LD_LIBRARY_PATH=$LD_LIBRARY_PATH

	test "`icegridadmin --version`" = $2 || \
		failed "icegridadmin version is incorrect"
	python -c "import Ice, sys; sys.exit(0 if Ice.__file__.endswith('ice-$2/python/Ice.py') else 1)" || \
		failed "python Ice version is incorrect"
}

test_ice_version ice331 3.3.1
test_ice_version ice342 3.4.2
test_ice_version ice350 3.5.0
test_ice_version ice351 3.5.1
