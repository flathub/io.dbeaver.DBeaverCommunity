#!/usr/bin/env python3

import os
import sys
import subprocess
import yaml
import json
import urllib.request
import shutil
import iso8601
import textwrap
from lxml import etree

MANIFEST = 'io.dbeaver.DBeaverCommunity.yml'
APPDATA = 'io.dbeaver.DBeaverCommunity.appdata.xml'


def parse_notes(notes):
    res = {}
    sec_name = ''
    for rn in notes.splitlines():
        if rn[:2] == '- ':
            sec_name = rn.replace("-", "", 1).strip()
            res[sec_name] = []
        else:
            res[sec_name].append(rn.replace("-", "", 1).strip())
    return res


with urllib.request.urlopen('https://api.github.com/repos/dbeaver/dbeaver/releases/latest') as url:
    RELEASEDATA = json.loads(url.read().decode())
    VERSION = RELEASEDATA['tag_name']

with open(MANIFEST, 'r') as yaml_file:
    data = yaml.load(yaml_file, Loader=yaml.FullLoader)

if VERSION in data['modules'][-1]['sources'][-1]['url']:
    print('No update needed. Current version: ' + VERSION)
    sys.exit()

old_url = data['modules'][-1]['sources'][-1]['url']
old_sha256 = data['modules'][-1]['sources'][-1]['sha256']
FILENAME = 'dbeaver-ce-' + VERSION + '-linux.gtk.x86_64.tar.gz'

new_url = 'https://github.com/dbeaver/dbeaver/releases/download/' + \
    VERSION + '/' + FILENAME

print('Downloading ' + FILENAME)
with urllib.request.urlopen(new_url) as response, open(FILENAME, 'wb') as out_file:
    shutil.copyfileobj(response, out_file)
print('Download complete')

# using replace, yaml reformats file funny

new_sha256 = subprocess.check_output(
    ['sha256sum', FILENAME]).decode("utf-8").split(None, 1)[0]

# Read in the file
with open(MANIFEST, 'r') as file:
    filedata = file.read()

# Replace the target string
filedata = filedata.replace(old_url, new_url)
filedata = filedata.replace(old_sha256, new_sha256)
# Write the file out again
with open(MANIFEST, 'w') as file:
    file.write(filedata)

release = etree.Element('release', {
    'version': VERSION,
    'date': iso8601.parse_date(RELEASEDATA['published_at']).strftime('%Y-%m-%d')
})
release.text = '\n            '
release.tail = '\n        '

description = etree.SubElement(release, 'description')
description.tail = '\n        '
description.text = '\n                '

ul = etree.SubElement(description, 'ul')
ul.tail = '\n            '
ul.text = '\n                    '

release_notes = textwrap.dedent(RELEASEDATA['body'])
release_notes = os.linesep.join([s for s in release_notes.splitlines() if s])
parsed_notes = parse_notes(release_notes)
for key in parsed_notes:
    li = etree.SubElement(ul, 'li')
    if key == list(parsed_notes.keys())[-1]:
        li.tail = '\n                '
    else:
        li.tail = '\n                    '
    # add description if exists
    if len(parsed_notes[key]) > 0:
        li.text = '%s\n                        ' % key
        ul2 = etree.SubElement(li, 'ul')
        ul2.tail = '\n                    '
        ul2.text = '\n                            '
        for desc in parsed_notes[key]:
            li2 = etree.SubElement(ul2, 'li')
            li2.text = desc
            if desc == parsed_notes[key][-1]:
                li2.tail = '\n                        '
            else:
                li2.tail = '\n                            '
    else:
        li.text = key


parser = etree.XMLParser(remove_comments=False)
tree = etree.parse(APPDATA, parser=parser)
releases = tree.find('releases')
old_releases = list(releases)[:5]
for child in list(releases):
    releases.remove(child)


releases.append(release)
for o_r in old_releases:
    releases.append(o_r)


tree.write(APPDATA, encoding="utf-8", xml_declaration=True)

os.remove(FILENAME)

print("Update done. New version: " + VERSION)
