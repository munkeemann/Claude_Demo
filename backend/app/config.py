"""Feature-toggle registry for the Package Router.

Toggles are plain named booleans kept in module state so they can be
flipped at runtime through the API (no restart). Add new toggles by
extending DEFAULT_TOGGLES.
"""

from threading import Lock
from typing import Dict

DEFAULT_TOGGLES: Dict[str, bool] = {}

_lock = Lock()
_toggles: Dict[str, bool] = dict(DEFAULT_TOGGLES)


def get_toggles() -> Dict[str, bool]:
    """Return a snapshot of all toggles and their current values."""
    with _lock:
        return dict(_toggles)


def is_enabled(name: str) -> bool:
    """Return the current value of a toggle (False if unknown)."""
    with _lock:
        return _toggles.get(name, False)


def set_toggle(name: str, value: bool) -> bool:
    """Set a toggle to an explicit value. Returns the new value.

    Raises KeyError for toggles that were never registered, so typos
    fail loudly instead of silently creating new flags.
    """
    with _lock:
        if name not in _toggles:
            raise KeyError(name)
        _toggles[name] = value
        return _toggles[name]


def flip_toggle(name: str) -> bool:
    """Invert a toggle and return its new value."""
    with _lock:
        if name not in _toggles:
            raise KeyError(name)
        _toggles[name] = not _toggles[name]
        return _toggles[name]


def reset_toggles() -> None:
    """Restore every toggle to its default value (used by tests)."""
    with _lock:
        _toggles.clear()
        _toggles.update(DEFAULT_TOGGLES)
