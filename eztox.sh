#!/bin/bash
set -o errexit

usage() {
	cat 1>&2 <<-DOC
	$0 [COMMAND] [OPTIONS]

	Options
	-------
	`
	grep '^while' -A 100 $0 | grep ';;' |
		sed -e 's/;;\|^[ \t]*\*).*//g' \
			 -e 's/;\([ ]*\)shift/ \1     /g' \
			 -e 's/^\([^)]*\))/\1/g' \
			 -e 's/^[ \t]*/  /g' \
			 -e 's/cmd=[^#]*#/  Command: /g' \
			 -e 's/[^ ]\+=true[^#]*#/  Flag: /gi' \
			 -e 's/[^ ]\+=false[^#]*#/  Flag: /gi' \
			 -e 's/="[\$0-9 ]*"[^#]*#/    Param: /g' \
			 -e 's/#//g'
	`
	  NOTE: This option list was auto-generated from: $0.
	DOC
}

PRJ_TOOLS="setup.py setup.cfg project.mk eztox"
PRJ_EXTRAS=".gitignore LICENSE.txt project.cfg"

log()   { $QUIET || echo $@ 1>&2; }
panic() { echo -n "PANIC:" 1>&2; echo $@ 1>&2; exit 1; }

backport() {
	backport_vars
	# copy all code to backport and to convert it to Py2
	rm -rf backport; mkdir -p backport   # flush backport dir
	cp -r $SRC backport                  # copy all code and configs
	pasteurize -j 8 -w --no-diff backport/ 2>/dev/null # transpile to Py2
	# change tag in main modle
	sed -i "s#^__tag__[ ]*=.*#__tag__ = 'py2'#" backport/$MAIN/__init__.py
	# ignore linter errors caused by transpiler
	sed -i 's#\(ignore[ ]*=[ ]*.*\)#\1,F401#g' backport/setup.cfg
}

uninstall(){
	for pip in $PIP pip2 pip3; do
		$pip uninstall -y $PKG 2>/dev/null || true
	done
}

clean(){ rm -rf .tox; }

backport_vars(){
	test "$PKG" != "backport" || panic "cannot build backport in backport"
	test -n "$MAIN"  || panic "MAIN is not set"
	test -n "$SRC"   || panic "SRC  is not set"
	test -n "$PKG"   || panic "PKG  is not set"
}

find_wheel(){ find dist -name "$PKG*$PY_TAG*.whl"; }

setup_vars(){
	WHEEL=`find_wheel`
	SETUP_DIR=`pwd`
	if test "$PY_TAG" = "py2"
	then SETUP_DIR=backport
	fi
}

project_vars() {
	test -n "$TARGET"  || panic "TARGET path must be set"
	test -n "$NEW_PRJ" || NEW_PRJ="`basename $TARGET`"
	test -n "$NEW_PRJ" || panic "cannot read project name from TARGET path: '$TARGET'"
}

copy_tools(){
	project_vars
	mkdir -p $TARGET            # create project path
	cp -f $PRJ_TOOLS  $TARGET/  # copy project tools that do not have any custom code/names
	log "copied tools: $PRJ_TOOLS -> $TARGET/"
	if $FORCE
	then cp -f $PRJ_EXTRAS $TARGET/; log "copied/updated extras: $PRJ_EXTRAS -> $TARGET/"
	else cp -n $PRJ_EXTRAS $TARGET/; log "safely copied extras:  $PRJ_EXTRAS -> $TARGET/"
	fi
}

not_exists(){
	local path="$1"
	local file="`basename "$path"`"
	if test -e $path && ! $FORCE
	then log "not creating $file: $path exists (use -f to overwrite)."; return 1
	else log -n "creating $file:";                                      return 0
	fi
}

generate_makefile() {
	project_vars
	not_exists $TARGET/Makefile || return 0
	if test -n "$MAIN"; then
		log "using MAIN=$MAIN as main module."
		cat > $TARGET/Makefile <<-MAKE
		MAIN         := $MAIN
		TEST_SCRIPTS := $MAIN -h
		include project.mk
		MAKE
	else
		log "using empty MAIN (use -m MAIN to set a custom main module)."
      cat > $TARGET/Makefile <<-MAKE
		include project.mk
		MAKE
	fi
}

generate_toxini(){
	project_vars
	not_exists $TARGET/tox.ini || return 0
	local envlist="envlist   = py36,py27,pypy"
	test -z "$TOXENV" || envlist="envlist   = $TOXENV"
	log "using $envlist."
	cat > $TARGET/tox.ini <<-INI
	[tox]
	$envlist
	skipsdist = True

	[testenv]
	deps =
		pytest
		flake8
		future

	commands = make dist-install {posargs:lint dist-test}
	whitelist_externals = make
	INI
}

generate_initpy(){
	project_vars
	not_exists $PKG_DIR/__init__.py || return 0
	cat > $PKG_DIR/__init__.py <<-PY
	# flake8: noqa: F401
	__version__ = "0.0.1"
	__tag__     = "py3"
	PY
	log "created $PKG_DIR/__init__.py"
}

generate_tests(){
	project_vars
	PRJ_TEST="$TARGET/tests/test_$NEW_PRJ.py"
	not_exists $PRJ_TEST || return 0
	PRJ_TEST_DEF="def test_$NEW_PRJ(): pass"
	mkdir -p `dirname $PRJ_TEST`
	echo "$PRJ_TEST_DEF" > $PRJ_TEST  # create a python test file
	log "created test: $PRJ_TEST."
}

generate_main(){
	touch $PKG_DIR/__main__.py    # make package runnable
}

user_name() { git config --get user.name  2>/dev/null || echo "$USER"; }
safe_name() { user_name | sed 's/[^a-z0-9_\.]/./gi'; }
user_email(){ git config --get user.email 2>/dev/null || echo "`safe_name`@gmail.com"; }
generate_readme(){
	project_vars
	not_exists $TARGET/README.md || return 0

	COPY_INFO="(c) Copyright `date +%Y`, `user_name`, `user_email`"
	log "using COPY_INFO=$COPY_INFO."
	cat > $TARGET/README.md <<-DOC
	$NEW_PRJ
	========

	Install via \`pip install $NEW_PRJ\`. Then run the program:

	    $NEW_PRJ --help       # show help
	    $NEW_PRJ              # run with defaults

	$COPY_INFO
	DOC
}

# The init_project command copies generic files required to use eztox in a new project.
# It also creates a Makefile that includes the generic `project.mk` to run all common
# project build and test tasks via `make`.
init_project(){
	project_vars
	copy_tools
	PKG_DIR="$TARGET/$NEW_PRJ"
	mkdir -p $PKG_DIR  # create package path
	log "created package: $PKG_DIR."
	generate_initpy
	generate_tests
	generate_makefile
	generate_readme
	generate_toxini
	cat 1>&2 <<-INFO
	#-------------------------------------------
	# Created new project: $NEW_PRJ in $TARGET!
	# You can now build it using make:
	#-------------------------------------------
	cd $TARGET
	make
	make dist
	# -------------------------------------------
	INFO
}

_tox(){
	if test -n "$TOXENV"
	then tox -e $TOXENV
	else tox
	fi
}

cmd=_tox
PIP=pip
TOXENV=''
TARGET=''
VERBOSE=false
QUIET=false
FORCE=false
TRACE=false

while test $# -gt 0; do case $1 in
	--pip)        PIP="$2";       shift;;  # set pip executable
	--pkg|-p)     PKG="$2";       shift;;  # set package name
	--src|-s)     SRC="$2";       shift;;  # set source files for building backport
	--main|-m)    MAIN="$2";      shift;;  # set main module
	--envlist|-e) TOXENV="$2";    shift;;  # set tox envlist 
	--trg|-t)     TARGET="$2";    shift;;  # set target dir for init or copy_tools
	--quiet|-q)   QUIET=true;;             # do not show log messages
	--force|-f)   FORCE=true;;             # force overwriting files
	--xtrace|-x)  TRACE=true;;             # set xtrace shell option
	--verbose|-v) VERBOSE=true;;           # set verbose shell option
	backport)     cmd=backport;;           # create Python 2 backport in subdir backport
	uninstall)    cmd=uninstall;;          # uninstall using pip2, pip3, and PIP
	clean)        cmd=clean;;              # clean .tox
	copy)         cmd=copy_tools;;         # copy eztox, setup.py etc to TARGET
	init)         cmd=init_project;;       # like copy, but also setup project files
	-h|--help)    cmd=usage;;              # show this help
	*)            panic "invalid command";;
esac; shift; done

# ! $VERBOSE || set -o verbose
log "running: $cmd"
! $VERBOSE || set -o verbose
! $TRACE   || set -o xtrace
$cmd

# vim: set ft=bash
