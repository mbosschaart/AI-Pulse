#!/usr/bin/env python3
"""Create the signed release enclosure after build.sh; private key stays in Keychain."""
from pathlib import Path
import datetime, email.utils, hashlib, json, subprocess, xml.etree.ElementTree as ET
root = Path(__file__).resolve().parents[1]
version = json.loads((root / 'Config/version.json').read_text())
archive = root / 'dist/AI-Pulse-macOS.zip'
sign = root / 'Vendor/bin/sign_update'
signature = subprocess.check_output([str(sign), '--account', 'AI-Pulse', '-p', str(archive)], text=True).strip()
subprocess.run([str(sign), '--account', 'AI-Pulse', '--verify', str(archive), signature], check=True)
namespace = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', namespace)
rss = ET.Element('rss', version='2.0')
channel = ET.SubElement(rss, 'channel')
ET.SubElement(channel, 'title').text = 'AI Pulse'
ET.SubElement(channel, 'link').text = 'https://github.com/mbosschaart/AI-Pulse'
ET.SubElement(channel, 'description').text = 'Signed AI Pulse releases'
item = ET.SubElement(channel, 'item')
ET.SubElement(item, 'title').text = 'AI Pulse ' + version['display']
ET.SubElement(item, 'pubDate').text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
ET.SubElement(item, '{'+namespace+'}version').text = version['build']
ET.SubElement(item, '{'+namespace+'}shortVersionString').text = version['display']
ET.SubElement(item, '{'+namespace+'}minimumSystemVersion').text = '14.0'
ET.SubElement(item, 'description').text = 'AI Pulse ' + version['display'] + '. See the GitHub release notes for changes.'
ET.SubElement(item, 'enclosure', {
    'url': 'https://github.com/mbosschaart/AI-Pulse/releases/download/v'+version['display']+'/AI-Pulse-macOS.zip',
    'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
    '{'+namespace+'}edSignature': signature,
})
ET.indent(rss)
ET.ElementTree(rss).write(root / 'appcast.xml', encoding='utf-8', xml_declaration=True)
(root / 'dist/SHA256SUMS.txt').write_text(hashlib.sha256(archive.read_bytes()).hexdigest()+'  AI-Pulse-macOS.zip\n')
print('Generated appcast.xml and dist/SHA256SUMS.txt for '+version['display'])
