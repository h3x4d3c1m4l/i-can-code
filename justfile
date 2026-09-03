default: install-flutter get-deps gen-code gen-l10n

set windows-shell := ["pwsh.exe", "-NoProfile", "-c"]

##
# Basic commands
##

install-flutter:
  fvm install -s --skip-pub-get

get-deps:
  fvm flutter pub get

gen-code:
  fvm dart run build_runner clean
  fvm dart run build_runner build

gen-l10n:
  fvm flutter gen-l10n

##
# Watching
##

watch-code:
  fvm dart run build_runner watch

##
# Building
##

build:
  fvm flutter build web

test:
  fvm flutter test

##
# Other commands
##

lint:
  fvm flutter analyze

show-outdated:
  fvm flutter pub outdated

upgrade-deps:
  fvm flutter pub upgrade
