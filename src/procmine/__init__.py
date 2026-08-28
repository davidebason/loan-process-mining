"""procmine - process-mining metrics over a loan-application event log.

Analytical logic lives here so that notebooks stay thin and every result is
reproducible and testable. The SQL that answers the business questions is
stored alongside as .sql files and executed through :mod:`procmine.db`.
"""

__version__ = "0.1.0"

__all__ = ["__version__"]
