#!/usr/bin/env python3
"""Read-only inspection of an IPA. Never edits or re-signs the archive.
A provisioning profile's APNs permission is not proof of the executable's
signed entitlement or Snapchat's server-side token/topic association.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
import tempfile
import zipfile

def embedded_plist(raw: bytes) -> dict | None:
    start=raw.find(b'<?xml'); end=raw.find(b'</plist>',start)
    if start<0 or end<0:return None
    try:
        value=plistlib.loads(raw[start:end+8])
        return value if isinstance(value,dict) else None
    except (ValueError,plistlib.InvalidFileException):return None

def main() -> int:
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa',type=Path)
    args=parser.parse_args()
    try:
        with zipfile.ZipFile(args.ipa) as archive:
            mains=[x for x in archive.namelist() if re.fullmatch(r'Payload/[^/]+\.app/Info\.plist',x)]
            if len(mains)!=1:raise ValueError('Expected one main Payload/*.app/Info.plist')
            info_entry=archive.getinfo(mains[0])
            if info_entry.file_size>1024*1024:raise ValueError('Info.plist exceeds 1 MiB')
            info=plistlib.loads(archive.read(info_entry)); prefix=mains[0][:-len('Info.plist')]
            report={'bundle_identifier':info.get('CFBundleIdentifier'),'version':info.get('CFBundleShortVersionString'),
                    'background_modes':info.get('UIBackgroundModes',[]),'file_sharing':bool(info.get('UIFileSharingEnabled')),
                    'profile_aps_environment':None,'signed_binary_aps_environment':'not inspected (macOS required)',
                    'snapchat_server_token_association':'not verifiable from an IPA'}
            profile_name=prefix+'embedded.mobileprovision'
            if profile_name in archive.namelist():
                p=archive.getinfo(profile_name)
                if p.file_size>10*1024*1024:raise ValueError('Provisioning profile is unexpectedly large')
                profile=embedded_plist(archive.read(p))
                if profile:report['profile_aps_environment']=profile.get('Entitlements',{}).get('aps-environment')
            if sys.platform=='darwin':
                exe=info.get('CFBundleExecutable','')
                if not isinstance(exe,str) or not exe or '/' in exe or exe in ('.','..'):raise ValueError('Invalid executable name')
                entry=archive.getinfo(prefix+exe)
                if entry.file_size>1024*1024*1024:raise ValueError('Executable exceeds 1 GiB')
                with tempfile.TemporaryDirectory(prefix='snapnotify-inspect-') as temp:
                    target=Path(temp)/'AppExecutable'
                    with archive.open(entry) as src,target.open('wb') as dst:
                        while chunk:=src.read(1024*1024):dst.write(chunk)
                    result=subprocess.run(['codesign','-d','--entitlements',':-',str(target)],capture_output=True,timeout=30,check=False)
                    entitlements=embedded_plist(result.stdout+result.stderr)
                    report['signed_binary_aps_environment']=entitlements.get('aps-environment') if entitlements else 'unreadable or absent'
            report['notes']=[
                'Missing/invalid aps-environment cannot be repaired by a local notification hook.',
                'Adding an Info.plist key does not grant APNs signing permission.',
                'Background audio mode alone does not guarantee a live Snapchat socket.',
                'No device tokens, certificates or provisioning identities are included in this output.'
            ]
            print(json.dumps(report,indent=2,ensure_ascii=False));return 0
    except (OSError,ValueError,zipfile.BadZipFile,KeyError,subprocess.TimeoutExpired,plistlib.InvalidFileException) as error:
        print(f'Inspection failed: {error}',file=sys.stderr);return 2
if __name__=='__main__':raise SystemExit(main())
