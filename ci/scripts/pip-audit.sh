#!/bin/sh
# pip-audit over every pinned CI requirements set (ci/requirements/*.txt).
set -eu
python3 -m venv /tmp/audit-venv
# shellcheck disable=SC1091 # created just above
. /tmp/audit-venv/bin/activate
pip install --quiet --upgrade pip
pip install --quiet -r ci/requirements/audit.txt
rc=0
for file in ci/requirements/*.txt; do
  echo "== ${file}"
  pip-audit --progress-spinner off --disable-pip --no-deps -r "${file}" || rc=1
done
exit "${rc}"
