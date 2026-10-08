from __future__ import annotations
import hashlib
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT=Path(__file__).resolve().parents[1]
class IPAInspectorTests(unittest.TestCase):
    def run_ipa(self,entries):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'test.ipa'
            with zipfile.ZipFile(p,'w') as z:
                for name,value in entries.items():z.writestr(name,value)
            before=hashlib.sha256(p.read_bytes()).hexdigest()
            result=subprocess.run([sys.executable,str(ROOT/'scripts/inspect_ipa.py'),str(p)],capture_output=True,text=True,check=False)
            self.assertEqual(before,hashlib.sha256(p.read_bytes()).hexdigest())
            return result
    def base(self):
        return {'Payload/Test.app/Info.plist':plistlib.dumps({'CFBundleIdentifier':'example.test','CFBundleExecutable':'Test','UIBackgroundModes':['audio']}),'Payload/Test.app/Test':b'not a signed Mach-O'}
    def test_missing_profile_not_claimed_valid(self):
        r=self.run_ipa(self.base());self.assertEqual(r.returncode,0,r.stderr)
        d=json.loads(r.stdout);self.assertIsNone(d['profile_aps_environment']);self.assertEqual(d['background_modes'],['audio'])
    def test_profile_permissions_distinct_from_signature(self):
        e=self.base();e['Payload/Test.app/embedded.mobileprovision']=b'CMS-prefix'+plistlib.dumps({'Entitlements':{'aps-environment':'development'}})+b'CMS-suffix'
        r=self.run_ipa(e);self.assertEqual(r.returncode,0,r.stderr);d=json.loads(r.stdout)
        self.assertEqual(d['profile_aps_environment'],'development');self.assertNotEqual(d['signed_binary_aps_environment'],'development')
    def test_multiple_apps_rejected(self):
        e=self.base();e['Payload/Other.app/Info.plist']=plistlib.dumps({});self.assertEqual(self.run_ipa(e).returncode,2)
    def test_invalid_info_rejected(self):
        self.assertEqual(self.run_ipa({'Payload/Test.app/Info.plist':b'not plist'}).returncode,2)
    def test_path_traversal_not_extracted(self):
        self.assertEqual(self.run_ipa({'Payload/../../Test.app/Info.plist':plistlib.dumps({})}).returncode,2)
    def test_sensitive_profile_data_omitted(self):
        e=self.base();e['Payload/Test.app/embedded.mobileprovision']=plistlib.dumps({'Entitlements':{'aps-environment':'development'},'DeveloperCertificates':[b'private-fixture'],'UUID':'secret-fixture-id'})
        r=self.run_ipa(e);self.assertNotIn('secret-fixture-id',r.stdout);self.assertNotIn('private-fixture',r.stdout)
if __name__=='__main__':unittest.main(verbosity=2)
