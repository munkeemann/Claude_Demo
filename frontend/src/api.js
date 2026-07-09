// Thin client for the Package Router backend.
const BASE = "http://localhost:8000";

async function req(path, options = {}) {
  const res = await fetch(`${BASE}${path}`, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    throw new Error(`${res.status} ${res.statusText}: ${detail}`);
  }
  return res.json();
}

export const api = {
  processOne: (pkg) => req("/packages/process", { method: "POST", body: JSON.stringify(pkg) }),
  processBatch: (pkgs) => req("/packages/process", { method: "POST", body: JSON.stringify(pkgs) }),
  samplePackages: () => req("/packages/sample"),
  consumersState: () => req("/consumers/state"),
  getConfig: () => req("/config"),
  setToggle: (name, value) =>
    req("/config/toggle", { method: "POST", body: JSON.stringify({ name, value }) }),
  reset: () => req("/reset", { method: "POST" }),
};
