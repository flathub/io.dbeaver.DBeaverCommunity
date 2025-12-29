#!/usr/bin/env bash

clear

#Update Flatpak SDKs and Platforms According to Manifest Requirements
flatpak install flathub org.gnome.Sdk//49 -y
flatpak install flathub org.gnome.Platform//49 -y
flatpak install flathub org.freedesktop.Sdk.Extension.openjdk//25.08 -y

flatpak-builder --repo=testing-repo --force-clean build-dir io.dbeaver.DBeaverCommunity.yml
flatpak --user remote-add --if-not-exists --no-gpg-verify db-testing-repo testing-repo
flatpak --user install db-testing-repo io.dbeaver.DBeaverCommunity -y
flatpak update -y
