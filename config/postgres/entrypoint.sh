#!/bin/sh
set -eu

if [ "$#" -eq 1 ] && [ "$1" = '--version' ]; then
  exec patroni --version
fi

umask 077
python3 - <<'PY'
import os
import re
import sys
from pathlib import Path

template = Path('/etc/patroni/patroni.yml.tmpl').read_text()
archive_enabled = os.environ.get('PATRONI_ARCHIVE_ENABLED', 'false').lower()
if archive_enabled not in ('true', 'false'):
    print('PATRONI_ARCHIVE_ENABLED must be true or false', file=sys.stderr)
    sys.exit(1)
settings = dict(os.environ)
settings['PATRONI_ARCHIVE_MODE'] = 'on' if archive_enabled == 'true' else 'off'
settings['PATRONI_ARCHIVE_COMMAND'] = 'pgbackrest --stanza=' + settings.get('PGBACKREST_STANZA', '') + ' archive-push %p' if archive_enabled == 'true' else ''
settings['PATRONI_RESTORE_COMMAND'] = 'pgbackrest --stanza=' + settings.get('PGBACKREST_STANZA', '') + ' archive-get %f "%p"' if archive_enabled == 'true' else ''
derived = {'PATRONI_ARCHIVE_MODE', 'PATRONI_ARCHIVE_COMMAND', 'PATRONI_RESTORE_COMMAND'}
required = set(re.findall(r'\$\{([A-Z0-9_]+)\}', template)) - derived
if archive_enabled == 'true':
    required.update({'PGBACKREST_STANZA', 'PGBACKREST_REPO1_PATH', 'PGBACKREST_PG1_PATH'})
missing = sorted(key for key in required if not os.environ.get(key))
if missing:
    print('Missing required settings: ' + ', '.join(missing), file=sys.stderr)
    sys.exit(1)
rendered = re.sub(r'\$\{([A-Z0-9_]+)\}', lambda match: settings[match.group(1)], template)
Path('/run/patroni/patroni.yml').write_text(rendered)
PY
exec "$@"
