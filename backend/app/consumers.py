"""In-memory consumer registry.

Each consumer keeps an ordered log of the packages it has received.
Rejected packages land in the dead-letter log with their reason code.
State is process-local by design — this is a demo harness, not a queue.
"""

from threading import Lock
from typing import Any, Dict, List


class ConsumerRegistry:
    """Holds per-consumer package logs plus the rejected/dead-letter log."""

    def __init__(self, categories: List[str]) -> None:
        self._lock = Lock()
        self._categories = list(categories)
        self._received: Dict[str, List[Dict[str, Any]]] = {c: [] for c in categories}
        self._rejected: List[Dict[str, Any]] = []

    def ensure_category(self, category: str) -> None:
        """Register a consumer lane if it doesn't exist yet (idempotent)."""
        with self._lock:
            if category not in self._received:
                self._categories.append(category)
                self._received[category] = []

    def deliver(self, category: str, record: Dict[str, Any]) -> None:
        """Append a routed package record to a consumer's log."""
        with self._lock:
            self._received.setdefault(category, []).append(record)

    def reject(self, record: Dict[str, Any]) -> None:
        """Append a rejected package record (must include 'reason')."""
        with self._lock:
            self._rejected.append(record)

    def state(self) -> Dict[str, Any]:
        """Snapshot for the UI: per-consumer counts + logs, and rejections."""
        with self._lock:
            return {
                "consumers": {
                    c: {"count": len(pkgs), "packages": list(pkgs)}
                    for c, pkgs in self._received.items()
                },
                "rejected": {
                    "count": len(self._rejected),
                    "packages": list(self._rejected),
                },
                "totalProcessed": sum(len(p) for p in self._received.values())
                + len(self._rejected),
            }

    def reset(self) -> None:
        """Clear every log (consumer lanes are kept, contents dropped)."""
        with self._lock:
            for c in self._received:
                self._received[c] = []
            self._rejected = []
