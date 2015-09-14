#!/bin/sh

#
# Bob the Builder - Work in progress.
#

set -x


#
# Configuration
#

DATESTAMP=`date '+%Y%m%d%H%M'`

# Where to fetch the code
REPO=https://github.com/mozilla/firefox-ios.git

# What branch or commit to checkout
REVISION=master

# Build ID - TODO Should be auto generated or come from the xcconfig file
BUILDID=$DATESTAMP

# Xcode scheme to build
BUILDSCHEME=FennecAurora

# Name of this build in generated assets
BUILDFLAVOUR=FennecAurora-L10N


#
# Generated names of things we use and build
#

BUILDNAME="${BUILDFLAVOUR}-${BUILDID}"
ASSETS="$BUILDNAME-Assets"

APPDELEGATE=FennecAurora-L10N.swift

PLIST="${BUILDNAME}.plist"
HTML="${BUILDNAME}.html"
IPA="${BUILDNAME}.ipa"


#
# Create a Python virtualenv with the python modules that we need
#

if [ -d python-env ]; then
  source python-env/bin/activate || exit 1
else
  virtualenv python-env || exit 1
  source python-env/bin/activate || exit 1
  brew install libxml2 || exit 1
  STATIC_DEPS=true pip install lxml || exit 1
fi


#
# We put all results in $BUILDNAME-Assets
#

mkdir $ASSETS


#
# Generate the .plist and .html. Substitute BUILDID, DATESTAMP, REVISION
# and BUILDSCHEME.
#

cp tmpl/$BUILDFLAVOUR.plist.tmpl $ASSETS/$PLIST
perl -pi -e "s/BUILDID/$BUILDID/g;" $ASSETS/$PLIST
perl -pi -e "s/BUILDNAME/$BUILDNAME/g;" $ASSETS/$PLIST
perl -pi -e "s/DATESTAMP/$DATESTAMP/g;" $ASSETS/$PLIST
perl -pi -e "s/REVISION/$REVISION/g;" $ASSETS/$PLIST
perl -pi -e "s/BUILDSCHEME/$BUILDSCHEME/g;" $ASSETS/$PLIST

cp tmpl/$BUILDFLAVOUR.html.tmpl $ASSETS/$HTML
perl -pi -e "s/BUILDID/$BUILDID/g;" $ASSETS/$HTML
perl -pi -e "s/BUILDNAME/$BUILDNAME/g;" $ASSETS/$HTML
perl -pi -e "s/DATESTAMP/$DATESTAMP/g;" $ASSETS/$HTML
perl -pi -e "s/REVISION/$REVISION/g;" $ASSETS/$HTML
perl -pi -e "s/BUILDSCHEME/$BUILDSCHEME/g;" $ASSETS/$HTML

# TODO Include the release notes in the HTML


#
# Clone the project into $BUILDNAME
#

if [ -d $BUILDNAME ]; then
  echo "There already is a $BUILDDIR checkout. Aborting to let you decide what to do."
  exit 1
fi

git clone $REPO $BUILDNAME || exit 1
cd $BUILDNAME || exit 1

git checkout $REVISION || exit 1


#
# Checkout our Carthage dependencies
#

./checkout.sh || exit 1


#
# Import locales
#

scripts/import-locales.sh || exit 1


#
# This is a big hack to get the right update check URLs in AuroraAppDelegate
# TODO Move these URLs to an xcconfig file that we can override/generate?
#

if [ -f "../tmpl/$APPDELEGATE" ]; then
  cp "../tmpl/$APPDELEGATE" Client/Application/AuroraAppDelegate.swift || exit 1
fi

#
# This is another big back to get the right build id in MOZ_BUILD_ID
# TODO This can probably be done with an xcconfig file too?
#

perl -pi -e "s/MOZ_BUILD_ID = \d+/MOZ_BUILD_ID = $BUILDID/" Client/Configuration/BaseConfig.xcconfig


#
# Make a build and export it
#

rm -rf ~/Library/Developer/Xcode/DerivedData
mkdir DerivedData || exit 1

xcrun xcodebuild archive \
    -jobs 1 \
    -derivedDataPath ./DerivedData \
    -archivePath ./$BUILDSCHEME.xcarchive \
    -project Client.xcodeproj \
    -scheme $BUILDSCHEME \
    -sdk iphoneos || exit 1


# TODO Is -skipUnavailableActions needed?


#
# Export to an enterprise .ipa
#

#xcodebuild \
#    -exportArchive \
#    -archivePath ./$BUILDNAME.xcarchive \
#    -exportFormat 'ipa' \
#    -exportPath ./$BUILDNAME.ipa \
#    -exportProvisioningProfile 'Fennec Aurora' || exit 1
#cp $BUILDNAME.ipa ../$ASSETS/ || exit 1

# Modern alternative that only works with Xcode 7
xcrun xcodebuild \
    -exportArchive \
    -archivePath ./$BUILDSCHEME.xcarchive \
    -exportPath ../$ASSETS \
    -exportOptionsPlist "Client/Configuration/${BUILDSCHEME}ExportOptions.plist"
mv ../$ASSETS/$BUILDSCHEME.ipa ../$ASSETS/$IPA


#
# Upload files to server
#

scp ../$ASSETS/$HTML people.mozilla.org:/home/iosbuilds/$HTML || exit 1
scp ../$ASSETS/$PLIST people.mozilla.org:/home/iosbuilds/$PLIST || exit 1
scp ../$ASSETS/$IPA people.mozilla.org:/home/iosbuilds/builds/$IPA || exit 1

ssh people.mozilla.org "ln -sf /home/iosbuilds/$PLIST /home/iosbuilds/$BUILDFLAVOUR.plist" || exit 1
ssh people.mozilla.org "ln -sf /home/iosbuilds/$HTML /home/iosbuilds/$BUILDFLAVOUR.html" || exit 1

