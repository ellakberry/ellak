#!/bin/sh
# vim: set et sw=2 ts=2 tw=0:
#
# adddepinfo.sh
#
# This script adds support for dependencies on Slackware
# repositories. It creates a "ghost" repository that only holds
# the dependency info and diverts all traffic to a real Slackware
# repository.
#
# You will need to have a directory with dependency files named
# "packagename.dep" for each package in the slackware repository. That
# file should include a comma separated list of dependencies.
#
# The script checks if there are any updated packages on the Slackware
# repository. If there are, the PACKAGES.TXT file is created again with
# dependency info from those .dep files.
#
# If you want to force the creation of a new PACKAGES.TXT file, even if
# there are no package updates in the Slackware repository, like if you
# update a .dep file, you can run the script with the "-f" switch.
#
# You can change the SLACKREPO variable to point the traffic to a
# different Slackware repository than the default one.
#
# If you want to allow the user to select another SLACKREPO, then
# run this script with the "-t" flag. You need to have a web server
# that can do mod_rewrite, .htaccess and php.
#
# Written by George Vlahavas <vlahavas~at~gmail~dot~com> for Salix
# Written by Cyrille Pontvieux <jrd~at~enialis~dot~net> for Salix
#
# some little changes  from ellakberry`at~gmail~dot~com for Ellakberry

# Licensed under the GPLv3
#

# default slackware base repository, please don't write the ending /
#SLACKREPO="http://mirrors.nix.org.ua/linux/slackwarearm"
#SLACKREPO="http://ftp.arm.slackware.com/slackwarearm"
#SLACKREPO="http://arm" # gia test prin apo lftp sto repos
SLACKREPO="http://repos.os.cs.teiath.gr/pub/ellakberry/14.0"
# space separated, starting and ending with a space
EXCLUDE=' arts k3b3 kdelibs3 qca-tls1 qca1 qt3 tightvnc '

#
# Don't touch anything after this
#
cd "$(dirname "$0")"
BASE_DIR=$(basename "$PWD")
#SLACKREPO_FULL="$SLACKREPO/$BASE_DIR"
SLACKREPO_FULL="$SLACKREPO/"
DEPSDIR="$PWD/deps"

forced=
templated=
while [ -n "$1" ]; do
  case "$1" in
    -f)
      forced=1
      ;;
    -t)
      templated=1
      ;;
  esac
  shift
done

# $1 : Subdirectory
# $2 : Repository directory
update_packages_txt() {
  SUBDIR="$1"
  REPODIR="$2"
  rm -f .CHECKSUMS.md5.new
  wget $SLACKREPO_FULL/$SUBDIR/CHECKSUMS.md5 -O .CHECKSUMS.md5.new || exit 1
  touch CHECKSUMS.md5
  if [ -n "$(diff CHECKSUMS.md5 .CHECKSUMS.md5.new)" ] || [ -n "$forced" ] ; then
    rm -f .PACKAGES.TXT.new .PACKAGES.TXT.salix .CHECKSUMS.md5.asc.new ChangeLog.txt
    wget $SLACKREPO_FULL/$SUBDIR/PACKAGES.TXT -O .PACKAGES.TXT.new || exit 1
    wget $SLACKREPO_FULL/$SUBDIR/CHECKSUMS.md5.asc -O .CHECKSUMS.md5.asc.new || exit 1
    wget $SLACKREPO_FULL/$SUBDIR/ChangeLog.txt
    if [ -n "$templated" ]; then
      echo -n "Adding dependency info to PACKAGES.TXT.tpl, this may take a while"
    else
      echo -n "Adding dependency info to PACKAGES.TXT, this may take a while"
    fi
    if [ -n "$templated" ]; then
      SLACKREPO_PLACEHOLDER='__SLACKREPO__'
    else
      SLACKREPO_PLACEHOLDER="$SLACKREPO_FULL/"
    fi
    for i in $(grep 'PACKAGE NAME:  .*t[gx]z$' .PACKAGES.TXT.new | sed 's/PACKAGE NAME:  //'); do
      echo -n "."
      PKGNAME=$(echo $i | sed 's/\(.*\)-\(.*\)-\(.*\)-\(.*\).t[gx]z/\1/')
      DEPS=$(cat $DEPSDIR/$PKGNAME.dep 2>/dev/null)
      CONFLICTS=$(cat $DEPSDIR/$PKGNAME.con 2>/dev/null)
      SUGGESTS=$(cat $DEPSDIR/$PKGNAME.sug 2>/dev/null)
      if echo "$EXCLUDE" | grep -q -v ".* $PKGNAME .*"; then  
        sed -n -e "/^PACKAGE NAME:  $i/!d; /^.\+$/{h;n}; :a /^.\+$/{H;n;ba};H;x; s/PACKAGE \(MIRROR\|REQUIRED\|CONFLICTS\|SUGGESTS\):[^\n]\+\n//g; s@\(PACKAGE NAME:[^\n]\+\n\)\(.*PACKAGE SIZE (uncompressed):[^\n]\+\n\)@\1PACKAGE MIRROR: ${SLACKREPO_PLACEHOLDER}${REPODIR}\n\2PACKAGE REQUIRED:  $DEPS\nPACKAGE CONFLICTS:  $CONFLICTS\nPACKAGE SUGGESTS:  $SUGGESTS\n@g;p;q" .PACKAGES.TXT.new >> .PACKAGES.TXT.salix
      fi
    done
    # Add an extra empty line before every entry, just in case
    sed -i "s/PACKAGE NAME:/\nPACKAGE NAME:/" .PACKAGES.TXT.salix
    # Prefer the solibs packages if none is installed
    sed -i 's/seamonkey|seamonkey-solibs/seamonkey-solibs|seamonkey/' .PACKAGES.TXT.salix
    sed -i 's/glibc|glibc-solibs/glibc-solibs|glibc/' .PACKAGES.TXT.salix
    sed -i 's/openssl|openssl-solibs/openssl-solibs|openssl/' .PACKAGES.TXT.salix
    if [ -n "$templated" ]; then
      mv -f .PACKAGES.TXT.salix PACKAGES.TXT.tpl
    else
      mv -f .PACKAGES.TXT.salix PACKAGES.TXT
      gzip -9 -c PACKAGES.TXT > PACKAGES.TXT.gz
    fi
    rm -f .PACKAGES.TXT.new
    mv -f .CHECKSUMS.md5.new CHECKSUMS.md5
    mv -f .CHECKSUMS.md5.asc.new CHECKSUMS.md5.asc
    echo ""
  else
    echo "No new packages found."
    rm .CHECKSUMS.md5.new
  fi
}

update_packages_txt '' ''
[ -d patches ] || mkdir patches
(
  cd patches
  update_packages_txt 'patches' ''
)
[ -d extra ] || mkdir extra
(
  cd extra
  update_packages_txt 'extra' 'extra/'
)
[ -d testing ] || mkdir testing
(
  cd testing
  update_packages_txt 'testing' 'testing/'
)
if [ -n "$templated" ] && [ ! -d .url ]; then
  ./.install-PACKAGES.TXT.sh "$SLACKREPO"
fi
