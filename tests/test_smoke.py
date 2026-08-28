"""Smoke test.

Deliberately trivial: its job is to prove that the package installs, imports,
and runs under CI before any real code exists.
"""

import procmine


def test_package_imports_and_reports_a_version() -> None:
    assert isinstance(procmine.__version__, str)
    assert procmine.__version__
