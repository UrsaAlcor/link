#!/bin/bash

set -xe

origin=$(pwd)
commit=$(git rev-parse HEAD)
version=$(git tag --points-at $commit)

if [ "$version" == "" ]; then
    echo "No tag found"
    version="0.0.0"
fi


install=$origin/lmod/dist/noarch/link/$version/bin
module=$origin/lmod/modules/noarch/link/

mkdir -p $install
mkdir -p $module

cp ld.lua $install/ld
cp link.lua $module/$version.lua

sed -i -e "s@\${package}@link@g" $module/$version.lua
sed -i -e "s@\${version}@$version@g" $module/$version.lua
