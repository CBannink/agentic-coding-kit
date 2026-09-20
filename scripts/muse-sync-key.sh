#!/bin/sh
# Stores the Muse subscription key in OpenCode's auth file (serverless).
# Requires a prior `muse login` (device-code OAuth). Muse CLI maintains
# ~/.config/muse/auth.json itself; this script copies the api_key it already
# stores into OpenCode's auth.json as {"muse-sub": {"type": "api", ...}},
# which OpenCode reads from disk on every launch. No local server, background
# process, or environment-variable timing is involved. Re-run if Muse CLI
# ever rotates the key, then restart OpenCode.
set -eu
python3 - <<'EOF'
import json, os, urllib.request
muse = json.load(open(os.path.expanduser('~/.config/muse/auth.json')))['providers']['meta']
key = muse.get('api_key')
if not key:
    raise SystemExit('No api_key in muse auth.json (providers.meta). Run `muse login` first.')
p = os.path.expanduser('~/.local/share/opencode/auth.json')
store = json.load(open(p)) if os.path.exists(p) else {}
store['muse-sub'] = {'type': 'api', 'key': key}
json.dump(store, open(p, 'w'), indent=2)
req = urllib.request.Request(muse['api_base_url'] + '/models',
                             headers={'Authorization': 'Bearer ' + key})
models = json.load(urllib.request.urlopen(req, timeout=30))['data']
print('muse-sub key stored in OpenCode auth.json.')
print('API check OK, models:', ', '.join(m['id'] for m in models[:8]))
EOF
