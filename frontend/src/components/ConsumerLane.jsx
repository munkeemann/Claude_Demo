import { useEffect, useRef, useState } from "react";
import { nodeRegistry, REASON_LABELS } from "../categories.js";

/** Animated count-up number. */
function CountUp({ value }) {
  const [display, setDisplay] = useState(value);
  const fromRef = useRef(value);

  useEffect(() => {
    const from = fromRef.current;
    if (from === value) return;
    const start = performance.now();
    const dur = 420;
    let raf;
    const tick = (now) => {
      const t = Math.min(1, (now - start) / dur);
      const eased = 1 - Math.pow(1 - t, 3);
      setDisplay(Math.round(from + (value - from) * eased));
      if (t < 1) raf = requestAnimationFrame(tick);
      else fromRef.current = value;
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
  }, [value]);

  return <span className="count">{display}</span>;
}

/**
 * One consumer lane: colored identity, live count, landing glow,
 * expandable log of received packages (or rejections with reason badges).
 */
export default function ConsumerLane({ lane, count, packages, landedAt, isRejected = false }) {
  const [open, setOpen] = useState(false);
  const [glow, setGlow] = useState(false);

  useEffect(() => {
    if (!landedAt) return;
    setGlow(true);
    const t = setTimeout(() => setGlow(false), 500);
    return () => clearTimeout(t);
  }, [landedAt]);

  const fmt = (v) => (v === null || v === undefined ? "—" : String(v));

  return (
    <section
      className={`lane ${glow ? "landed" : ""}`}
      style={{ "--lane-color": lane.color }}
      ref={(el) => {
        nodeRegistry.lanes[lane.key] = el;
      }}
    >
      <div className="lane-head" onClick={() => setOpen((o) => !o)}>
        <span className="dot" />
        <span className="name">{lane.label}</span>
        <span className="range">{lane.range}</span>
        <span className="spacer" />
        <CountUp value={count} />
        <span className={`chev ${open ? "open" : ""}`}>▼</span>
      </div>
      {open && (
        <div className="lane-body">
          {packages.length === 0 ? (
            <div className="lane-empty">
              {isRejected ? "Nothing rejected — clean run so far." : "No packages received yet."}
            </div>
          ) : (
            packages
              .slice(-60)
              .reverse()
              .map((p, i) => (
                <div className="pkg-row" key={`${p.trackingNumber}-${i}`}>
                  <span className="tn mono">{p.trackingNumber}</span>
                  <span className="dims mono">
                    {fmt(p.lengthIn)}×{fmt(p.widthIn)}×{fmt(p.heightIn)}
                  </span>
                  {isRejected ? (
                    <span className="badge">{REASON_LABELS[p.reason] || p.reason}</span>
                  ) : (
                    <span className="vol mono">{Math.round(p.volume).toLocaleString()} in³</span>
                  )}
                </div>
              ))
          )}
        </div>
      )}
    </section>
  );
}
