#!/usr/bin/env bash

set -o errexit

dir=.cache/test_images

rm -f $dir/dist/*.whl
mkdir -p $dir/dist

main_script="
	RUN makepy init -t demo1
	RUN makepy init -t /demo2
	RUN makepy init -t demo3 -p demo.three
	RUN mkdir -p demo4 && cd demo4 && makepy init
	RUN mkdir -p demo5 && cd demo5 && makepy init -p demo.five
	RUN apk add \$PY-pytest
	RUN cd demo1 && makepy test
	RUN cd demo2 && makepy test
	RUN cd demo3 && makepy test
	RUN cd demo4 && makepy test
	RUN cd demo5 && makepy test
	RUN \$PIP freeze | grep demo1
	RUN \$PIP freeze | grep demo2
	RUN \$PIP freeze | grep demo-three
	RUN \$PIP freeze | grep demo4
	RUN \$PIP freeze | grep demo-five
"

for deps in "git"; do
for pkgs in "'tox<3.0.0'" "structlog" "colorama"; do
for py in 2 3; do
	whl=`find dist -name "*py$py-none-any.whl"`
	echo "copying wheel: $whl"
	test -e $dir/$whl || cp $whl $dir/dist
	cat > $dir/mp$py.Dockerfile <<-DF
	FROM alpine:3.7
	RUN apk add -U py$py-pip python$py bash bash-completion coreutils
	RUN test -e /usr/bin/python || cp /usr/bin/python$py /usr/bin/python
	ENV PIP pip$py
	ENV PY  py$py
	RUN \$PIP install wheel
	ADD dist /dist
	RUN ls -la /dist
	RUN \$PIP install $whl
	# 1. Test with default packages.
	$main_script
	# 2. Test with extra apks.
	RUN apk add $deps
	$main_script
	# 3. Test with extra pip packages.
	RUN \$PIP install $pkgs
	$main_script
	DF
	echo "
##########################################
TESTING: PYTHON:$py, DEPS:$deps, PKGS:$pks
##########################################
	"
	docker build $dir -t alpine:makepy-$py -f $dir/mp$py.Dockerfile
done
done
done
