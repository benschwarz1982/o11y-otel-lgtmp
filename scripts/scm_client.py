"""
Branch/commit/merge-request helpers for the self-service scripts, for
whichever platform runs them: GitHub Actions (pull requests, see
github_client.py) or GitLab CI (merge requests, see gitlab_client.py).
"""
import os
import sys

if os.environ.get("GITHUB_ACTIONS") == "true":
    from github_client import create_branch, create_commit, create_merge_request

    TOKEN_VARIABLE = "GITHUB_TOKEN"
    PLATFORM = "GitHub Actions"
else:
    from gitlab_client import create_branch, create_commit, create_merge_request

    TOKEN_VARIABLE = "GITLAB_API_TOKEN"
    PLATFORM = "GitLab CI"

__all__ = ["create_branch", "create_commit", "create_merge_request", "require_ci_token"]


def require_ci_token() -> None:
    """Exit unless the API token of the current CI platform is present."""
    if not os.environ.get(TOKEN_VARIABLE):
        print(
            f"This script only runs inside CI ({PLATFORM} needs {TOKEN_VARIABLE} - "
            "see README.md#onboarding-process).",
            file=sys.stderr,
        )
        sys.exit(1)
