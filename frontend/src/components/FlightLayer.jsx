import { useEffect, useRef } from "react";
import { nodeRegistry } from "../categories.js";

/**
 * Renders in-flight package chips and animates each along
 * queue → processor → destination lane using the Web Animations API
 * (compositor-driven transforms = smooth at 60fps).
 */
export default function FlightLayer({ flights, speed, onLanded }) {
  return (
    <div className="flight-layer">
      {flights.map((f) => (
        <Chip key={f.id} flight={f} speed={speed} onLanded={onLanded} />
      ))}
    </div>
  );
}

function center(el) {
  const r = el.getBoundingClientRect();
  return { x: r.left + r.width / 2, y: r.top + r.height / 2 };
}

function Chip({ flight, speed, onLanded }) {
  const ref = useRef(null);
  const doneRef = useRef(false);

  useEffect(() => {
    const el = ref.current;
    const queueEl = nodeRegistry.queue;
    const procEl = nodeRegistry.processor;
    const laneEl = nodeRegistry.lanes[flight.category];
    if (!el || !queueEl || !procEl || !laneEl) {
      onLanded(flight);
      return;
    }

    const q = center(queueEl);
    const p = center(procEl);
    // land just inside the lane's left edge, vertically centered
    const laneRect = laneEl.getBoundingClientRect();
    const l = { x: laneRect.left + 70, y: laneRect.top + laneRect.height / 2 };

    const w = el.offsetWidth / 2;
    const h = el.offsetHeight / 2;
    const at = (pt) => `translate(${pt.x - w}px, ${pt.y - h}px)`;

    const duration = Math.max(350, 950 / speed);
    const anim = el.animate(
      [
        { transform: `${at(q)} scale(0.7)`, opacity: 0, offset: 0 },
        { transform: `${at(q)} scale(1)`, opacity: 1, offset: 0.08 },
        { transform: `${at(p)} scale(1)`, opacity: 1, offset: 0.42 },
        { transform: `${at(p)} scale(1.12)`, opacity: 1, offset: 0.52 },
        { transform: `${at(l)} scale(1)`, opacity: 1, offset: 0.94 },
        { transform: `${at(l)} scale(0.6)`, opacity: 0, offset: 1 },
      ],
      { duration, easing: "cubic-bezier(0.35, 0, 0.25, 1)", fill: "forwards" }
    );
    anim.onfinish = () => {
      if (!doneRef.current) {
        doneRef.current = true;
        onLanded(flight);
      }
    };
    return () => anim.cancel();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div ref={ref} className="chip" style={{ "--chip-color": flight.color, top: 0, left: 0 }}>
      <span className="cdot" />
      {flight.label}
    </div>
  );
}
