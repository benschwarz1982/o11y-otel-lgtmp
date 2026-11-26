# Pinned Python requirements for CI jobs

Every `pip install` in `.gitlab-ci.yml` installs one of the `*.txt`
files here - never a bare package name. Each `.txt` is generated from
the `.in` next to it and pins every package, transitive ones included.

| Set | Used by |
|---|---|
| `python-lint` | `validate:python` |
| `ansible-lint` | `validate:ansible` |
| `onboarding` | `validate:manifests`, `tenants:create-mr`, `tenants:update-mr`, `tenants:offboarding-mr`, `tenants:apply` |
| `audit` | `validate:python-deps` |

`validate:python-deps` runs `pip-audit` over all four `.txt` files.

## Changing or updating a set

Edit the `.in` file (top-level packages only), then regenerate the
`.txt` with the same Python version the jobs run on (`python:3.15.2-slim`)
- a different Python version can resolve to different pins:

```bash
cd ci/requirements
docker run --rm -v "$PWD:/w" -w /w -u "$(id -u):$(id -g)" -e HOME=/tmp \
  python:3.15.2-slim sh -c '
    python3 -m venv /tmp/v && . /tmp/v/bin/activate &&
    pip install --quiet pip-tools &&
    pip-compile --quiet --strip-extras --upgrade \
      --output-file <set>.txt <set>.in'
```

`--upgrade` moves every pin to its latest version; drop it to only
resolve what the `.in` change needs. Never edit a `.txt` by hand.
