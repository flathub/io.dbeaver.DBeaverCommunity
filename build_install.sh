#!/usr/bin/env bash

clear
flatpak-builder --repo=testing-repo --force-clean build-dir io.dbeaver.DBeaverCommunity.yml
flatpak --user remote-add --if-not-exists --no-gpg-verify db-testing-repo testing-repo
flatpak --user install db-testing-repo io.dbeaver.DBeaverCommunity -y
flatpak update -y
