// Category metadata — single source for colors/labels so every surface
// (lanes, chips, counts, charts) stays consistent.

export const LANES = [
  { key: "small", label: "Small", range: "< 1,000 in³", color: "var(--cat-small)" },
  { key: "medium", label: "Medium", range: "1,000 – 7,999 in³", color: "var(--cat-medium)" },
  { key: "large", label: "Large", range: "≥ 8,000 in³", color: "var(--cat-large)" },
];

export const REJECTED = {
  key: "rejected",
  label: "Rejected",
  range: "dead letter",
  color: "var(--cat-rejected)",
};

export const REASON_LABELS = {
  MISSING_DIMENSIONS: "Missing dims",
  INVALID_DIMENSIONS: "Invalid dims",
  TYPE_ERROR: "Type error",
  OUT_OF_RANGE: "Out of range",
};

// Mutable registry of DOM nodes the flight layer animates between.
export const nodeRegistry = { queue: null, processor: null, lanes: {} };
