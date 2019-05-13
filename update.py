#!/usr/bin/env python3

import os
import sys
import subprocess
import json
import urllib.request
import shutil
import iso8601
from lxml import etree

MANIFEST = 'io.dbeaver.DBeaverCommunity.json'
APPDATA = 'io.dbeaver.DBeaverCommunity.appdata.xml'

with urllib.request.urlopen('https://api.github.com/repos/dbeaver/dbeaver/releases/latest') as url:
    RELEASEDATA = json.loads(url.read().decode())
    VERSION = RELEASEDATA['tag_name']

with open(MANIFEST, 'r') as json_file:
    data = json.load(json_file)

if VERSION in data['modules'][-1]['sources'][-1]['url']:
    print('No update needed. Current version: ' + VERSION)
    sys.exit()

source_entry = data['modules'][-1]['sources'][-1]
source_entry['url'] = 'https://github.com/dbeaver/dbeaver/releases/download/' + VERSION + '/dbeaver-ce-' + VERSION + '-linux.gtk.x86_64.tar.gz'
FILENAME = 'dbeaver-ce-' + VERSION + '-linux.gtk.x86_64.tar.gz'

print('Downloading ' + FILENAME)
with urllib.request.urlopen(source_entry['url']) as response, open(FILENAME, 'wb') as out_file:
    shutil.copyfileobj(response, out_file)
print('Download complete')

source_entry['sha256'] = subprocess.check_output(['sha256sum', FILENAME]).decode("utf-8").split(None, 1)[0]
source_entry['size'] = os.path.getsize(FILENAME)

with open(MANIFEST, 'w') as json_file:
    json.dump(data, json_file, indent=4)

release = etree.Element('release', {
    'version': VERSION,
    'date': iso8601.parse_date(RELEASEDATA['published_at']).strftime('%Y-%m-%d')
})

description = etree.SubElement(release,'description')
description.text = RELEASEDATA['body']

parser = etree.XMLParser(remove_comments=False)
tree = etree.parse(APPDATA, parser=parser)
releases = tree.find('releases')
for child in list(releases):
    releases.remove(child)
release.tail = '\n  '
releases.append(release)
tree.write(APPDATA, encoding="utf-8", xml_declaration=True)

os.remove(FILENAME)

print("Update done. New version: " + VERSION)
