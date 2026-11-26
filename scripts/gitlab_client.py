"""
GitLab API calls shared by scripts/create-{onboarding,update,offboarding}-mr.py
(branch -> commit -> merge request), with retries that are safe for
non-idempotent POSTs.

Found live: gitlab.com did not answer a branch creation within the 30 s
read timeout and the onboarding job failed. A plain retry of a POST is
not safe - the first attempt may have succeeded server-side after the
client gave up, and a second one then fails ("Branch already exists",
"Another open merge request already exists") or duplicates work. So
after a timeout, connection error or 5xx, each helper first checks
whether its own effect is already there, and only resends if it isn't.

Auth: GITLAB_API_TOKEN, not CI_JOB_TOKEN - CI_JOB_TOKEN reliably 404s on
repository endpoints (branches/commits) even for this same project, a
long-standing GitLab limitation (see e.g.
https://gitlab.com/gitlab-org/gitlab/-/issues/482639). See
docs/self-service.md#processes for how to create the token.
"""
import os
import sys
import time
from urllib.parse import quote

import requests

ATTEMPTS = 3
BACKOFF_SECONDS = 10
TIMEOUT_SECONDS = 30


class _Retryable(Exception):
    pass


def _request(method: str, path: str, **kwargs) -> requests.Response:
    """One API call. Raises _Retryable on timeouts/connection errors/5xx."""
    url = f"{os.environ['CI_API_V4_URL']}/projects/{os.environ['CI_PROJECT_ID']}{path}"
    headers = {"PRIVATE-TOKEN": os.environ["GITLAB_API_TOKEN"]}
    try:
        response = requests.request(method, url, headers=headers, timeout=TIMEOUT_SECONDS, **kwargs)
    except (requests.Timeout, requests.ConnectionError) as e:
        raise _Retryable(f"{method} {path}: {e}") from e
    if response.status_code >= 500:
        raise _Retryable(f"{method} {path}: HTTP {response.status_code}")
    if not response.ok:
        print(f"GitLab API error ({response.status_code}) on {method} {path}: {response.text}", file=sys.stderr)
        response.raise_for_status()
    return response


def _get_with_retries(fn):
    """Idempotent reads: plain retries."""
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return fn()
        except _Retryable as e:
            print(f"Lookup attempt {attempt}/{ATTEMPTS} failed: {e}", file=sys.stderr)
            if attempt == ATTEMPTS:
                raise
            time.sleep(BACKOFF_SECONDS)


def _with_retries(action, already_done):
    """
    Run a non-idempotent action(). After EVERY retryable failure (the last
    one too), check with already_done() whether it took effect anyway
    (returns its result, None = not there); only then resend. If that
    check itself can't be answered, stop - resending blindly could
    duplicate the action. A conflict ("already exists") after such an
    ambiguous attempt is checked the same way: the earlier attempt may
    have completed only after the check said it hadn't.
    """
    ambiguous = False
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return action()
        except requests.HTTPError as e:
            status = e.response.status_code if e.response is not None else None
            if ambiguous and status in (400, 409):
                done = _get_with_retries(already_done)
                if done is not None:
                    print("...an earlier attempt had succeeded after all - continuing.", file=sys.stderr)
                    return done
            raise
        except _Retryable as e:
            ambiguous = True
            print(f"Attempt {attempt}/{ATTEMPTS} failed: {e}", file=sys.stderr)
            time.sleep(BACKOFF_SECONDS)
            try:
                done = _get_with_retries(already_done)
            except _Retryable as lookup_error:
                raise RuntimeError(
                    "GitLab did not answer, and whether the request took effect could not be "
                    "verified either - check the project's branches/merge requests before "
                    "retrying this job."
                ) from lookup_error
            if done is not None:
                print("...but it had succeeded server-side - continuing.", file=sys.stderr)
                return done
            if attempt == ATTEMPTS:
                raise RuntimeError(f"GitLab request failed {ATTEMPTS} times, nothing was created") from e
    raise AssertionError("unreachable")


def _branch(name: str):
    try:
        return _request("GET", f"/repository/branches/{quote(name, safe='')}").json()
    except requests.HTTPError as e:
        if e.response is not None and e.response.status_code == 404:
            return None
        raise


def create_branch(name: str, ref: str) -> str:
    """Create branch `name` at `ref`; returns the commit SHA it points at."""
    # Resolve a symbolic ref (the default branch name, when CI_COMMIT_SHA
    # isn't set) to its commit SHA first - the check below compares SHAs.
    ref = _get_with_retries(lambda: _request("GET", f"/repository/commits/{quote(ref, safe='')}").json()["id"])

    def already_done():
        branch = _branch(name)
        # Only "ours" if it still points at the requested base - a branch
        # that existed before with other content is a real conflict.
        return True if branch and branch["commit"]["id"] == ref else None

    _with_retries(
        lambda: _request("POST", "/repository/branches", params={"branch": name, "ref": ref}),
        already_done,
    )
    return ref


def create_commit(branch: str, parent: str, message: str, actions: list[dict]) -> None:
    """Commit `actions` onto a branch currently at commit `parent`."""

    def already_done():
        # Ours only if it sits directly on `parent` - the branch's base
        # may itself carry the same title (an earlier update of the same
        # system, fast-forward merged).
        head = _branch(branch)
        if not head:
            return None
        commit = head["commit"]
        ours = commit["title"] == message.splitlines()[0] and commit.get("parent_ids") == [parent]
        return True if ours else None

    _with_retries(
        lambda: _request(
            "POST",
            "/repository/commits",
            json={"branch": branch, "commit_message": message, "actions": actions},
        ),
        already_done,
    )


def create_merge_request(payload: dict) -> dict:
    def already_done():
        existing = _request(
            "GET",
            "/merge_requests",
            params={"source_branch": payload["source_branch"], "state": "opened"},
        ).json()
        return existing[0] if existing else None

    return _with_retries(lambda: _request("POST", "/merge_requests", json=payload).json(), already_done)
