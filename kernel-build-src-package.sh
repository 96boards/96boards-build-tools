#!/bin/bash

set -e

trap cleanup 1 2 3 6 15

# TODO:
# * Add RPM support
# * Make the CI job consume this script

# For now we expect the user to run this command on a Debian based system
DEP_PKGS="quilt devscripts cpio rsync rpm"

function error()
{
	echo "$*"
	exit 1
}

function cleanup()
{
	echo "Cleaning up..."
	rm -rf $BUILD_DIR
}

function usage()
{
	cat <<EOF
Usage: $(basename $0) -k <kernel git url> -b <kernel git branch> -c <kernel config path>

Generates a debian and rpm kernel source package for a custom kernel tree.

Options:

Required:
 -k <kernel git url>
	Kernel git URL used for clonning the tree
 -b <kernel git branch.
	Kernel branch to be used
 -c <kernel config path>
	Path for the config file to be used (available as part of the git tree)

Additional:

 -r <kernel git reference repository>
	Local repository to be used as reference (git clone --reference)
 -i <custom build id>
	Custom build id to be added at the package version (e.g. linaro.X-1)

EOF
}

# Check if all the require debian packages are installed
function check_pkgs()
{
	for pkg in $DEP_PKGS; do
		dpkg -s $pkg > /dev/null 2>&1 || error "Missing dependency, please install package $pkg."
	done
}

function check_env()
{
	if [ "$DEBEMAIL" = "" ] || [ "$DEBFULLNAME" = "" ]; then
		error "Please set DEBEMAIL and DEBFULLNAME in your environment."
	fi
}

CUSTOM_BUILD_ID=1
KERNEL_GIT_REFERENCE=
KERNEL_GIT_URL=https://git.linaro.org/people/amit.kucheria/kernel.git
KERNEL_GIT_BRANCH=96b-kernelci
KERNEL_CONFIG="arch/arm64/configs/distro.config"
OUT_DIR=$(pwd)/out
BUILD_DIR=$(mktemp -d)

while [ "$1" != "" ]; do
	case $1 in
		"/h" | "/?" | "-?" | "-h" | "--help" )
			usage
			exit
			;;
        "-k" )
            shift
            KERNEL_GIT_URL="$1"
            ;;
        "-b" )
            shift
            KERNEL_GIT_BRANCH="$1"
            ;;
        "-c" )
            shift
            KERNEL_CONFIG="$1"
            ;;
        "-r" )
            shift
            KERNEL_GIT_REFERENCE="--reference $1"
            ;;
        "-i" )
            shift
            CUSTOM_BUILD_ID="$1"
            ;;
        *)
			error "Internal error"
            ;;
	esac
	shift
done

check_pkgs
check_env

cd ${BUILD_DIR}

# Checkout source code
git clone -b ${KERNEL_GIT_BRANCH} ${KERNEL_GIT_URL} ${KERNEL_GIT_REFERENCE} linux
git clone --depth 1 https://git.linaro.org/ci/debian-kernel-packaging.git debian-pkg

# Export the kernel packaging version
cd linux

## To use when we switch to 4.5, since -rc is higher than the final tag
# kernel_version=`make kernelversion | sed -e 's/\.0-rc/~rc/'

kernel_version=`make kernelversion`
export KERNEL_GIT_VERSION=`git log --format="%H" -1`
export KDEB_PKGVERSION="${kernel_version}.linaro.${CUSTOM_BUILD_ID}-1"
git tag v${kernel_version}

cd ..

# Build the debian source kernel
cd debian-pkg

# Allow our own versioning scheme
sed -i 's/dfsg/linaro/g' debian/bin/genorig.py debian/lib/python/debian_linux/debian.py

# Use build number as ABI
sed -i "s/^abiname:.*/abiname: ${CUSTOM_BUILD_ID}/g" debian/config/defines

cat << EOF > debian/changelog
linux ($KDEB_PKGVERSION) jessie; urgency=medium

  * Auto build:
    - URL: ${KERNEL_GIT_URL}
    - Branch: ${KERNEL_GIT_BRANCH}
    - Hash: ${KERNEL_GIT_VERSION}

 -- ${DEBFULLNAME} <${DEBEMAIL}>  `date "+%a, %d %b %Y %T %z"`

EOF

# Use the kernel config from the kernel tree
cp ../linux/${KERNEL_CONFIG} debian/config/arm64/config

debian/rules clean || true
debian/bin/genorig.py ../linux
debian/rules orig
fakeroot debian/rules source
debuild -S -uc -us
cd ..

# Build rpm source package
rpmversion=${kernel_version//-*/}
git clone --depth 1 -b c7-aarch64 git://git.centos.org/rpms/kernel-aarch64.git
cd kernel-aarch64
sed -i "s/\%define rpmversion.*/\%define rpmversion $rpmversion/g" SPECS/kernel-aarch64.spec
sed -i "s/\%define pkgrelease.*/\%define pkgrelease reference.${CUSTOM_BUILD_ID}/g" SPECS/kernel-aarch64.spec
sed -i "s/\%define signmodules 1/\%define signmodules 0/g" SPECS/kernel-aarch64.spec
sed -i "s/mv linux-\%{rheltarball}/mv linux-\*/g" SPECS/kernel-aarch64.spec
sed -i '/\%{_libexecdir}\/perf-core\/\*/a\%{_datadir}\/perf-core\/\*' SPECS/kernel-aarch64.spec
cp ../linux/${KERNEL_CONFIG} SOURCES/config-arm64-redhat

# Make sure config is sane for centos
sed -i "s/CONFIG_ATA=.*/CONFIG_ATA=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_ATA_PIIX=.*/CONFIG_ATA_PIIX=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_AUTOFS4_FS=.*/CONFIG_AUTOFS4_FS=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_SATA_AHCI=.*/CONFIG_SATA_AHCI=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_SATA_AHCI_PLATFORM=.*/CONFIG_SATA_AHCI_PLATFORM=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_AHCI_HIP05=.*/CONFIG_AHCI_HIP05=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_AMD_XGBE=.*/CONFIG_AMD_XGBE=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_SCSI_HISI_SAS=.*/CONFIG_SCSI_HISI_SAS=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_IPV6=.*/CONFIG_IPV6=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_HNS_MDIO=.*/CONFIG_HNS_MDIO=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_HNS=.*/CONFIG_HNS=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_HNS_DSAF=.*/CONFIG_HNS_DSAF=y/g" SOURCES/config-arm64-redhat
sed -i "s/CONFIG_HNS_ENET=.*/CONFIG_HNS_ENET=y/g" SOURCES/config-arm64-redhat

cp ../orig/*.orig.tar.xz SOURCES/linux-${rpmversion}-reference.${CUSTOM_BUILD_ID}.tar.xz
rpmbuild --nodeps --define "%_topdir `pwd`" -bs SPECS/kernel-aarch64.spec
cd ..

# Copy back the resulted artifacts
mkdir -p $OUT_DIR
cp -p $BUILD_DIR/linux_* $BUILD_DIR/kernel-aarch64/SRPMS/*.src.rpm $OUT_DIR
echo "Source packages available at $OUT_DIR"

# Clean-up
cleanup
