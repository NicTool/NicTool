#!/bin/sh

VERSION=$1
if [ -z "$VERSION" ]; then
	echo "$0 ver1 ver2"
	exit 2
fi
if [ -z "$2" ]; then
	echo "$0 ver1 ver2"
	exit 2
fi

alias gfind='find . -type d -name node_modules -prune     -o -type d -name .git -prune     -o -type d -name .build -prune     -o -type d -name bower_components -prune     -o -type f -print'

grep $VERSION `gfind` | cut -f1 -d':' | sort -u > versions.txt
sed -i '' \
	-e "/version/ s/$1/$2/" \
	-e "/VERSION/ s/$1/$2/" \
	-e "/v$1/ s/$1/$2/" \
	`cat versions.txt`
rm versions.txt

