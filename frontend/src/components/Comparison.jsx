import { useEffect, useState } from "react";
import { api } from "../api.js";
import { GIGANTIC_LANE, GIGANTIC_TOGGLE, LANES } from "../categories.js";

const ALL_CATS = [...LANES, GIGANTIC_LANE];

/**
 * Before/After comparison — the money slide.
 *
 * Runs the full sample dataset twice against the live backend (toggle
 * OFF, then ON), restores the toggle to what the user had, and renders
 * a side-by-side bar chart plus the exact packages that moved
 * Large → Gigantic.
 */
export default function Comparison({ originalToggle, onClose, onDone }) {
  const [phase, setPhase] = useState("running"); // running | done | error
  const [data, setData] = useState(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const sample = await api.samplePackages();

        await api.reset();
        await api.setToggle(GIGANTIC_TOGGLE, false);
        const before = await api.processBatch(sample);

        await api.reset();
        await api.setToggle(GIGANTIC_TOGGLE, true);
        const after = await api.processBatch(sample);

        // put the world back the way the user had it
        await api.reset();
        await api.setToggle(GIGANTIC_TOGGLE, originalToggle);

        if (cancelled) return;

        const count = (results, cat) =>
          results.results.filter((r) => r.category === cat).length;
        const counts = ALL_CATS.map((c) => ({
          ...c,
          before: count(before, c.key),
          after: count(after, c.key),
        }));

        const afterByTn = new Map(after.results.map((r) => [r.trackingNumber, r]));
        const moved = before.results
          .filter((r) => r.category === "large")
          .map((r) => ({ ...r, after: afterByTn.get(r.trackingNumber) }))
          .filter((r) => r.after?.category === "gigantic")
          .sort((a, b) => b.volume - a.volume);

        setData({ counts, moved, total: sample.length });
        setPhase("done");
        onDone();
      } catch (e) {
        if (!cancelled) setPhase("error");
      }
    })();
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const max = data ? Math.max(...data.counts.flatMap((c) => [c.before, c.after]), 1) : 1;

  return (
    <div className="modal-veil" onClick={phase !== "running" ? onClose : undefined}>
      <div className="modal comparison" onClick={(e) => e.stopPropagation()}>
        <h2>Routing impact — Gigantic category</h2>
        <div className="sub">
          Full {data?.total ?? 100}-package dataset, processed with <b>ENABLE_GIGANTIC_CATEGORY</b>{" "}
          off vs. on (KAN-20).
        </div>

        {phase === "running" && (
          <div className="cmp-loading">
            <div className="cmp-spinner" />
            Running both scenarios against the live router…
          </div>
        )}

        {phase === "error" && (
          <div className="cmp-loading">Comparison failed — is the backend running?</div>
        )}

        {phase === "done" && data && (
          <>
            <div className="cmp-chart">
              {data.counts.map((c) => (
                <div className="cmp-group" key={c.key}>
                  <div className="cmp-bars">
                    <div className="cmp-bar-wrap">
                      <span className="cmp-val">{c.before}</span>
                      <div
                        className="cmp-bar before"
                        style={{
                          height: `${(c.before / max) * 100}%`,
                          "--bar-color": c.color,
                        }}
                      />
                    </div>
                    <div className="cmp-bar-wrap">
                      <span className="cmp-val">{c.after}</span>
                      <div
                        className="cmp-bar after"
                        style={{
                          height: `${(c.after / max) * 100}%`,
                          "--bar-color": c.color,
                        }}
                      />
                    </div>
                  </div>
                  <div className="cmp-cat">
                    <span className="dot" style={{ background: c.color }} />
                    {c.label}
                  </div>
                  {c.after !== c.before && (
                    <div className={`cmp-delta ${c.after > c.before ? "up" : "down"}`}>
                      {c.after > c.before ? "+" : ""}
                      {c.after - c.before}
                    </div>
                  )}
                </div>
              ))}
              <div className="cmp-legend">
                <span><i className="lg before" /> Toggle off</span>
                <span><i className="lg after" /> Toggle on</span>
              </div>
            </div>

            <h3 className="cmp-moved-title">
              {data.moved.length} packages move Large → Gigantic
            </h3>
            <div className="cmp-moved">
              {data.moved.map((m) => (
                <div className="cmp-moved-row" key={m.trackingNumber}>
                  <span className="mono tn">{m.trackingNumber}</span>
                  <span className="mono vol">{Math.round(m.volume).toLocaleString()} in³</span>
                  <span className="path">
                    <b style={{ color: "var(--cat-large)" }}>Large</b>
                    <span className="arrow">→</span>
                    <b style={{ color: "var(--cat-gigantic)" }}>Gigantic</b>
                  </span>
                </div>
              ))}
            </div>

            <div className="modal-actions">
              <button className="primary" onClick={onClose}>Close</button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
