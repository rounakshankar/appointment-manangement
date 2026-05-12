# Re-export settings so that `from cacms.config import settings` continues to work
# after cacms/config.py was converted to a package.
from cacms.config.settings import settings  # noqa: F401

__all__ = ["settings"]
