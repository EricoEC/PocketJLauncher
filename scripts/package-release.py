#!/usr/bin/env python3
"""Package v1.6 IPA/TIPA from a Release app without personal signing material."""
import argparse
import hashlib
import mmap
import os
from pathlib import Path
import plistlib
import shutil
import stat
import subprocess
import tempfile
import zipfile

SOURCE = Path(__file__).resolve().parents[1]
MACHO = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf', b'\xbf\xba\xfe\xca'}

def run(args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, capture_output=True, **kwargs)

def plist(data):
    if not data.lstrip().startswith((b'<?xml', b'bplist')):
        data = b'<?xml version="1.0" encoding="UTF-8"?>\n' + data
    return plistlib.loads(data)

def macho(path):
    if path.is_symlink() or not path.is_file(): return False
    with path.open('rb') as handle: return handle.read(4) in MACHO

def copy_file(src, dst):
    # copy2/cp -p can copy Finder and File Provider metadata, breaking signing.
    shutil.copyfile(src, dst)
    os.chmod(dst, stat.S_IMODE(os.stat(src).st_mode))
    return dst

def ignored(directory, names):
    return [n for n in names if n in {'.DS_Store', '_CodeSignature', '__MACOSX'} or n.endswith(('.mobileprovision', '.provisionprofile'))]

def signing_markers(app):
    markers = {b'Q42CQ5VP5A'}
    for profile in app.rglob('*.mobileprovision'):
        info = plist(run(['security', 'cms', '-D', '-i', profile]).stdout)
        for field in ['ProvisionedDevices', 'TeamIdentifier', 'ApplicationIdentifierPrefix']:
            for value in info.get(field, []): markers.add(value.encode())
    return markers

def sanitize(value, markers):
    if isinstance(value, dict):
        return {k: sanitize(v, markers) for k, v in value.items() if k != 'com.apple.developer.team-identifier'}
    if isinstance(value, list): return [sanitize(v, markers) for v in value]
    if isinstance(value, str):
        for marker in markers:
            prefix = marker.decode(errors='ignore') + '.'
            if value.startswith(prefix): value = value[len(prefix):]
    return value

def entitlements(path):
    result = run(['ldid', '-e', path]).stdout
    return plist(result) if result.strip() else {}

def sign(path, values, temporary):
    temporary.write_bytes(plistlib.dumps(values))
    run(['codesign', '--force', '--sign', '-', '--timestamp=none', '--generate-entitlement-der', '--entitlements', temporary, path])

def audit(app, expected, markers):
    info = plist((app / 'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'com.Erico.PocketJLauncher'
    assert info['CFBundleShortVersionString'] == info['CFBundleVersion'] == '1.6'
    helper = app / 'Extensions/PocketJJITHelper.appex'
    helper_info = plist((helper / 'Info.plist').read_bytes())
    assert helper_info['CFBundleShortVersionString'] == helper_info['CFBundleVersion'] == '1.6'
    assert (helper / 'Frameworks/StikJIT.framework/StikJIT').is_file()
    assert (app / 'Frameworks/libpocketj_pairing.dylib').is_file()
    assert 'localdevvpn' in info['LSApplicationQueriesSchemes']
    assert '_remotepairing-pairable-host._tcp' in info['NSBonjourServices']
    assert info['UIFileSharingEnabled'] and 'audio' in info['UIBackgroundModes']
    assert entitlements(app / info['CFBundleExecutable']) == expected
    assert (app / 'PocketJPairing-THIRD-PARTY-NOTICES.txt').is_file()
    assert (app / 'LICENSE').is_file() and (app / 'NOTICE.md').is_file()
    for path in app.rglob('*'):
        if path.is_symlink():
            assert path.resolve().is_relative_to(app.resolve()), f'External symlink: {path.relative_to(app)}'
            continue
        assert not path.name.endswith(('.mobileprovision', '.provisionprofile', '.p12', '.pfx', '.mobiledevicepairing'))
        assert path.name not in {'.DS_Store', '__MACOSX'}
        if not path.is_file() or not path.stat().st_size: continue
        with path.open('rb') as handle, mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ) as data:
            assert all(data.find(marker) < 0 for marker in markers), f'Personal signing marker: {path.relative_to(app)}'
        if macho(path):
            metadata = run(['codesign', '-d', '--verbose=4', path]).stderr
            assert b'Signature=adhoc' in metadata, f'Non-ad-hoc signature: {path.relative_to(app)}'
            assert b'com.apple.developer.team-identifier' not in run(['ldid', '-e', path]).stdout
    run(['codesign', '--verify', '--deep', '--strict', app])
    exports = run(['xcrun', 'dyld_info', '-exports', app / info['CFBundleExecutable']]).stdout
    assert any(line.split()[-1:] == [b'_main'] for line in exports.splitlines())

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    args.app = args.app.resolve(); args.output = args.output.resolve()
    assert args.app.is_dir() and args.app.suffix == '.app'
    cache = Path.home() / 'Library/Caches/PocketJLauncher/v1.6'
    cache.mkdir(parents=True, exist_ok=True)
    markers = signing_markers(args.app)
    variants = [('', 'ipa', 'entitlements.sideload.xml'), ('-TrollStore', 'tipa', 'entitlements.trollstore.xml')]
    names = [f'PocketJLauncher-v1.6-iOS{suffix}.{ext}' for suffix, ext, _ in variants]
    args.output.mkdir(parents=True, exist_ok=True)
    for name in names:
        if (args.output / name).exists(): raise FileExistsError(f'Refusing to overwrite existing release: {name}')
    with tempfile.TemporaryDirectory(prefix='release-package-', dir=cache) as temp:
        work = Path(temp); staged = []
        for (suffix, ext, permission), name in zip(variants, names):
            payload = work / ext / 'Payload'; payload.mkdir(parents=True)
            app = payload / 'PocketJLauncher.app'
            shutil.copytree(args.app, app, symlinks=True, copy_function=copy_file, ignore=ignored)
            for name_file in ['LICENSE', 'NOTICE.md']:
                copy_file(SOURCE / name_file, app / name_file)
            shutil.copytree(SOURCE / 'THIRD_PARTY_LICENSES', app / 'THIRD_PARTY_LICENSES', symlinks=True, copy_function=copy_file, ignore=ignored)
            binaries = [p for p in app.rglob('*') if macho(p)]
            original = {p: sanitize(entitlements(p), markers) for p in binaries}
            temporary = work / 'entitlements.plist'
            expected = plist((SOURCE / permission).read_bytes())
            for binary in binaries: sign(binary, original[binary], temporary)
            bundles = [p for p in app.rglob('*') if p.is_dir() and not p.is_symlink() and p.suffix in {'.framework', '.appex', '.xpc', '.bundle', '.app'}]
            for bundle in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
                info_file = bundle / 'Info.plist'
                if not info_file.is_file(): continue
                executable = plist(info_file.read_bytes()).get('CFBundleExecutable')
                if executable and (bundle / executable).exists(): sign(bundle, original.get(bundle / executable, {}), temporary)
            sign(app, expected, temporary)
            audit(app, expected, markers)
            print(f'{ext.upper()}: {len(binaries)} Mach-O files re-signed; metadata, permissions and privacy checks passed.', flush=True)
            archive = work / name
            run(['zip', '-X', '-y', '-9', '-q', '-r', archive, 'Payload'], cwd=payload.parent)
            with zipfile.ZipFile(archive) as zipped:
                assert zipped.testzip() is None
                assert all(n.startswith('Payload/') for n in zipped.namelist())
                root_info = plist(zipped.read('Payload/PocketJLauncher.app/Info.plist'))
                assert root_info['CFBundleShortVersionString'] == '1.6'
            staged.append((archive, args.output / name))
            print(f'{ext.upper()}: ZIP integrity passed.', flush=True)
        for source, target in staged: os.replace(source, target)
    sums = ''.join(f'{hashlib.file_digest((args.output / name).open("rb"), "sha256").hexdigest()}  {name}\n' for name in names)
    (args.output / 'SHA256SUMS.txt').write_text(sums)
    print('Both release packages and SHA256SUMS.txt are ready.', flush=True)

if __name__ == '__main__': main()
