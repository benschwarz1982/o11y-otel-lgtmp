"""
GitHub API calls for scripts/create-{onboarding,update,offboarding}-mr.py
(branch -> commit -> pull request) - same interface as gitlab_client.py,
picked by scm_client.py when the scripts run inside GitHub Actions.

The commit is built with the Git Data API (blobs/tree/commit/ref), so
no git push and no checkout credentials are needed; commits created
this way are signed by GitHub.

Auth: GITHUB_TOKEN (env) - the onboarding workflow passes either a
GitHub App installation token (preferred: pull requests it opens trigger
the CI workflow) or the job's own GITHUB_TOKEN (pull requests opened
with it do not start workflows - see README "GitHub Actions").

Same retry rules as gitlab_client.py: reads are retried plainly; a
non-idempotent write is only resent after checking that the first
attempt did not take effect server-side.
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
    api = os.environ.get("GITHUB_API_URL", "https://api.github.com")
    url = f"{api}/repos/{os.environ['GITHUB_REPOSITORY']}{path}"
    headers = {
        "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    try:
        response = requests.request(method, url, headers=headers, timeout=TIMEOUT_SECONDS, **kwargs)
    except (requests.Timeout, requests.ConnectionError) as e:
        raise _Retryable(f"{method} {path}: {e}") from e
    if response.status_code >= 500:
        raise _Retryable(f"{method} {path}: HTTP {response.status_code}")
    if not response.ok:
        print(f"GitHub API error ({response.status_code}) on {method} {path}: {response.text}", file=sys.stderr)
        response.raise_for_status()
    return response


def _get_with_retries(fn):
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return fn()
        except _Retryable as e:
            print(f"Lookup attempt {attempt}/{ATTEMPTS} failed: {e}", file=sys.stderr)
            if attempt == ATTEMPTS:
                raise
            time.sleep(BACKOFF_SECONDS)


def _with_retries(action, already_done):
    """Same semantics as gitlab_client._with_retries."""
    ambiguous = False
    for attempt in range(1, ATTEMPTS + 1):
        try:
            return action()
        except requests.HTTPError as e:
            status = e.response.status_code if e.response is not None else None
            if ambiguous and status in (409, 422):
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
                    "GitHub did not answer, and whether the request took effect could not be "
                    "verified either - check the repository's branches/pull requests before "
                    "re-running this workflow."
                ) from lookup_error
            if done is not None:
                print("...but it had succeeded server-side - continuing.", file=sys.stderr)
                return done
            if attempt == ATTEMPTS:
                raise RuntimeError(f"GitHub request failed {ATTEMPTS} times, nothing was created") from e
    raise AssertionError("unreachable")


def _branch_sha(name: str):
    try:
        return _request("GET", f"/git/ref/heads/{quote(name, safe='/')}").json()["object"]["sha"]
    except requests.HTTPError as e:
        if e.response is not None and e.response.status_code == 404:
            return None
        raise


def create_branch(name: str, ref: str) -> str:
    """Create branch `name` at `ref`; returns the commit SHA it points at."""
    sha = _get_with_retries(lambda: _request("GET", f"/commits/{quote(ref, safe='')}").json()["sha"])

    def already_done():
        return True if _branch_sha(name) == sha else None

    _with_retries(
        lambda: _request("POST", "/git/refs", json={"ref": f"refs/heads/{name}", "sha": sha}),
        already_done,
    )
    return sha


def _tree_entry(action: dict) -> dict:
    """GitLab-style commit action -> GitHub tree entry (text inline, base64 as blob)."""
    entry = {"path": action["file_path"], "mode": "100644", "type": "blob"}
    if action["action"] == "delete":
        entry["sha"] = None
    elif action["action"] in ("create", "update"):
        if action.get("encoding") == "base64":
            blob = _request("POST", "/git/blobs", json={"content": action["content"], "encoding": "base64"}).json()
            entry["sha"] = blob["sha"]
        else:
            entry["content"] = action["content"]
    else:
        raise ValueError(f"Unsupported commit action: {action['action']}")
    return entry


def create_commit(branch: str, parent: str, message: str, actions: list[dict]) -> None:
    """Commit `actions` onto a branch currently at commit `parent`."""
    # Blobs and trees are content-addressed: creating them twice is harmless.
    base_tree = _get_with_retries(lambda: _request("GET", f"/git/commits/{parent}").json()["tree"]["sha"])
    entries = [_get_with_retries(lambda a=a: _tree_entry(a)) for a in actions]
    tree = _get_with_retries(
        lambda: _request("POST", "/git/trees", json={"base_tree": base_tree, "tree": entries}).json()["sha"]
    )
    commit = _get_with_retries(
        lambda: _request(
            "POST", "/git/commits", json={"message": message, "tree": tree, "parents": [parent]}
        ).json()["sha"]
    )

    def already_done():
        return True if _branch_sha(branch) == commit else None

    # Moving the branch is the only step with a visible effect; force=false
    # makes a lost race fail instead of overwriting someone else's commit.
    _with_retries(
        lambda: _request("PATCH", f"/git/refs/heads/{quote(branch, safe='/')}", json={"sha": commit, "force": False}),
        already_done,
    )


def create_merge_request(payload: dict) -> dict:
    """Open a pull request from a GitLab-style merge request payload."""
    owner = os.environ["GITHUB_REPOSITORY"].split("/")[0]

    def already_done():
        existing = _request(
            "GET",
            "/pulls",
            params={"head": f"{owner}:{payload['source_branch']}", "state": "open"},
        ).json()
        return {"web_url": existing[0]["html_url"]} if existing else None

    def open_pr():
        pr = _request(
            "POST",
            "/pulls",
            json={
                "title": payload["title"],
                "head": payload["source_branch"],
                "base": payload["target_branch"],
                "body": payload.get("description", ""),
                "maintainer_can_modify": True,
            },
        ).json()
        return {"web_url": pr["html_url"]}

    return _with_retries(open_pr, already_done)
