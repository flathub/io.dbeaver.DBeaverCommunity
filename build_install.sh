#!/usr/bin/env bash

clear

#Update Flatpak SDKs and Platforms According to Manifest Requirements
flatpak install flathub org.gnome.Sdk//50 -y
flatpak install flathub org.gnome.Platform//50 -y
flatpak install flathub org.freedesktop.Sdk.Extension.openjdk21//25.08 -y

flatpak-builder --repo=testing-repo --force-clean build-dir io.dbeaver.DBeaverCommunity.yml
flatpak --user remote-delete db-testing-repo
flatpak --user remote-add --no-gpg-verify --no-enumerate db-testing-repo testing-repo
flatpak --user install -y db-testing-repo io.dbeaver.DBeaverCommunity
flatpak update -y
