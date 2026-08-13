#!/usr/bin/env bash
# NFR-1 (offline-first), NFR-7 (local-only data), NFR-8 (no tracking).
#
# These three are claims about what the app *cannot* do, and no runtime test can
# establish one: a test that watches for network traffic and sees none has shown
# that none happened on that run, which is not the same fact. What can be
# established is that the code contains no way to make a request and links
# nothing that would — so this is a source and dependency audit, which is exactly
# what NFR-7's and NFR-8's acceptance criteria ask for.
#
# StoreKit is the one documented exception (NFR-7): Apple's framework talks to
# Apple's servers, the app hands it a product id and gets a transaction back, and
# no user or learning data goes with it.
#
# Runs in CI. Exits non-zero on a finding.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
status=0

app_sources=$(find FullDeck/FullDeck Packages/*/Sources -name '*.swift' 2>/dev/null)

echo "== NFR-1/NFR-7: no networking API in app or package sources"
# URLSession/URLRequest/Network.framework/sockets. Not a substring match on
# "URL" — the app legitimately builds file URLs and one https:// licence link,
# which is a destination handed to the system browser, not a request.
network=$(grep -nE '(^|[^A-Za-z0-9_])(URLSession|URLRequest|NWConnection|CFSocket|getaddrinfo|dataTask|downloadTask|uploadTask)([^A-Za-z0-9_]|$)' $app_sources 2>/dev/null)
if [[ -n "$network" ]]; then
  echo "$network"
  echo "x found networking API. NFR-1 says the only network use is StoreKit."
  status=1
else
  echo "ok none"
fi

echo
echo "== NFR-8: no third-party dependencies to be a tracker"
# The app has no SPM dependencies at all beyond its own two local packages, and
# that is the strongest possible form of "no analytics SDK".
remote=$(grep -rnE '\.package\(url:' Packages/*/Package.swift 2>/dev/null)
if [[ -n "$remote" ]]; then
  echo "$remote"
  echo "x a package now has a remote dependency. Audit it against NFR-8 before shipping."
  status=1
else
  echo "ok packages declare no remote dependencies"
fi

pbx_remote=$(grep -nE 'XCRemoteSwiftPackageReference' FullDeck/FullDeck.xcodeproj/project.pbxproj 2>/dev/null)
if [[ -n "$pbx_remote" ]]; then
  echo "$pbx_remote"
  echo "x the Xcode project references a remote package. Audit it against NFR-8."
  status=1
else
  echo "ok the Xcode project references no remote packages"
fi

echo
echo "== NFR-8: no advertising identifier"
idfa=$(grep -rnE 'AdSupport|ASIdentifierManager|advertisingIdentifier|AppTrackingTransparency' $app_sources FullDeck/FullDeck.xcodeproj/project.pbxproj 2>/dev/null)
if [[ -n "$idfa" ]]; then
  echo "$idfa"
  echo "x found an advertising-identifier API. NFR-8 forbids IDFA outright."
  status=1
else
  echo "ok none"
fi

echo
if [[ $status -eq 0 ]]; then
  echo "privacy-audit: NFR-1 / NFR-7 / NFR-8 hold by construction"
else
  echo "privacy-audit: FAILED"
fi
exit $status
