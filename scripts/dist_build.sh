#!/usr/bin/env bash
set -e

# Get the parent directory of where this script is.
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ] ; do SOURCE="$(readlink "$SOURCE")"; done
DIR="$( cd -P "$( dirname "$SOURCE" )/.." && pwd )"

# Change into that dir because we expect that.
cd "$DIR"

# Get the git commit
GIT_COMMIT="$(git rev-parse --short HEAD)"
GIT_IMPORT="github.com/tendermint/tendermint/version"

# Determine the arch/os combos we're building for
XC_ARCH=${XC_ARCH:-"386 amd64 arm"}
XC_OS=${XC_OS:-"solaris darwin freebsd linux windows"}
XC_EXCLUDE=${XC_EXCLUDE:-" darwin/arm solaris/amd64 solaris/386 solaris/arm freebsd/amd64 windows/arm "}

# Make sure build tools are available.
go get -u github.com/tendermint/glide

# Get VENDORED dependencies
make get_vendor_deps

# Build!
# ldflags: -s Omit the symbol table and debug information.
#	         -w Omit the DWARF symbol table.
echo "==> Building..."
IFS=' ' read -ra arch_list <<< "$XC_ARCH"
IFS=' ' read -ra os_list <<< "$XC_OS"
for arch in "${arch_list[@]}"; do
	for os in "${os_list[@]}"; do
		if [[ "$XC_EXCLUDE" !=  *" $os/$arch "* ]]; then
			echo "--> $os/$arch"
			GOOS=${os} GOARCH=${arch} go build -ldflags "-s -w -X ${GIT_IMPORT}.GitCommit=${GIT_COMMIT}" -tags="${BUILD_TAGS}" -o "build/pkg/${os}_${arch}/tendermint" ./cmd/tendermint
		fi
	done
done

# Zip all the files.
echo "==> Packaging..."
for PLATFORM in $(find ./build/pkg -mindepth 1 -maxdepth 1 -type d); do
	OSARCH=$(basename "${PLATFORM}")
	echo "--> ${OSARCH}"

	pushd "$PLATFORM" >/dev/null 2>&1
	zip "../${OSARCH}.zip" ./*
	popd >/dev/null 2>&1
done

exit 0
