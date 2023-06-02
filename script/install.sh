#!/bin/sh

# Automated installer for amusewiki

set -e

# enforce the correct path
cd `dirname $0`
cd ..

echo "Working in `pwd`"

missing='no'
for command in perl carton fc-cache update-mime-database xapian-check openssl \
               cpanm \
               make wget git unzip rsync gs; do
    echo -n "Checking if $command is present: "
    if which $command > /dev/null; then
        echo "YES"
    else
        if [ $command = 'xapian-check' ]; then
            echo "NO, please install xapian and its utils"
        elif [ $command = 'make' ]; then
            echo "NO, please install build essential utils"
        elif [ $command = 'fc-cache' ]; then
            echo "NO, please install fontconfig"
        elif [ $command = 'gs' ]; then
            echo "NO, please install ghostscript"
        else
            echo "NO, please install $command"
        fi
        missing='yes'
    fi
done

if [ "$missing" != "no" ]; then
    cat <<EOF
Missing core utilities, cannot proceed. Please install them:

 - a working perl with carton and cpanm (i.e., you can install modules)
 - fontconfig (install it before installing texlive)
 - a mime-info database: shared-mime-info on debian
 - openssl
 - general utils: wget, git, unzip, rsync
EOF
    exit 2
fi

echo "Installing perl modules"
export PERL_USE_UNSAFE_INC=1
carton install --deployment || cpanm -L local --installdeps .
export PERL_USE_UNSAFE_INC=""

. ./script/add-texlive-to-path.sh

echo -n "Checking installation of TeX live: "
if which xelatex > /dev/null; then
    echo "OK"
else
    echo "TeXlive is packaged for a lot of OSes and you're suggested"
    echo "to install it (in its full variant) from the repository."
    echo "Otherwise see https://www.tug.org/texlive/"
    echo "A non-interactive script is provided under script/install-texlive.sh"
    exit 2
fi

echo "Installing needed JS"
script/install_js.sh
echo "Installing fonts"
script/install_fonts.sh


echo "Creating fontspec.json"
carton exec script/amusewiki-populate-webfonts

echo "Installing cgit"
carton exec script/install-cgit.pl

echo "All installed, ready to be configured"
