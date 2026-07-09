import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "./api.js";
import {
  GIGANTIC_LANE,
  GIGANTIC_TICKET,
  GIGANTIC_TOGGLE,
  LANES,
  REJECTED,
  nodeRegistry,
} from "./categories.js";
import Comparison from "./components/Comparison.jsx";
import ConsumerLane from "./components/ConsumerLane.jsx";
import FlightLayer from "./components/FlightLayer.jsx";
import PackageBuilder, { randomPackage } from "./components/PackageBuilder.jsx";

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const BASE_INTERVAL_MS = 230; // per-package pacing at 1× (≈23s for the full dataset)

const EMPTY_COUNTS = { small: 0, medium: 0, large: 0, gigantic: 0, rejected: 0 };
const EMPTY_LOGS = { small: [], medium: [], large: [], gigantic: [], rejected: [] };

const CHAOS_PRESETS = [
  { label: "Missing dims", pkg: { trackingNumber: "CHAOS-MISSING", weightLbs: 5 } },
  { label: "Negative dims", pkg: { trackingNumber: "CHAOS-NEGATIVE", lengthIn: -8, widthIn: 10, heightIn: 4, weightLbs: 3 } },
  { label: "Text in number field", pkg: { trackingNumber: "CHAOS-TEXT", lengthIn: "twelve", widthIn: 10, heightIn: 4, weightLbs: 2 } },
  { label: "Absurdly huge", pkg: { trackingNumber: "CHAOS-HUGE", lengthIn: 4000, widthIn: 200, heightIn: 90, weightLbs: 99999 } },
  { label: "Empty package", pkg: {}, full: true },
];

let chipId = 0;

export default function App() {
  const [counts, setCounts] = useState(EMPTY_COUNTS);
  const [logs, setLogs] = useState(EMPTY_LOGS);
  const [landed, setLanded] = useState({}); // laneKey -> timestamp (glow trigger)
  const [flights, setFlights] = useState([]);
  const [queueRemaining, setQueueRemaining] = useState(null);
  const [processed, setProcessed] = useState(0);
  const [total, setTotal] = useState(0);
  const [running, setRunning] = useState(false);
  const [speed, setSpeed] = useState(1);
  const [builderOpen, setBuilderOpen] = useState(false);
  const [compareOpen, setCompareOpen] = useState(false);
  const [giganticOn, setGiganticOn] = useState(false);
  const [toasts, setToasts] = useState([]);
  const speedRef = useRef(1);
  const stopRef = useRef(false);

  useEffect(() => {
    speedRef.current = speed;
  }, [speed]);

  // pick up the toggle's server-side value on load
  useEffect(() => {
    api
      .getConfig()
      .then((c) => setGiganticOn(!!c.toggles[GIGANTIC_TOGGLE]))
      .catch(() => {});
  }, []);

  const toast = useCallback((msg, err = false) => {
    const id = ++chipId;
    setToasts((t) => [...t, { id, msg, err }]);
    setTimeout(() => setToasts((t) => t.filter((x) => x.id !== id)), 3600);
  }, []);

  /** Pull authoritative state from the backend into the lane logs. */
  const refreshState = useCallback(async () => {
    const state = await api.consumersState();
    setLogs({
      small: state.consumers.small?.packages ?? [],
      medium: state.consumers.medium?.packages ?? [],
      large: state.consumers.large?.packages ?? [],
      gigantic: state.consumers.gigantic?.packages ?? [],
      rejected: state.rejected.packages,
    });
    setCounts({
      small: state.consumers.small?.count ?? 0,
      medium: state.consumers.medium?.count ?? 0,
      large: state.consumers.large?.count ?? 0,
      gigantic: state.consumers.gigantic?.count ?? 0,
      rejected: state.rejected.count,
    });
  }, []);

  /** KAN-20: flip the Gigantic toggle at runtime — no restart. */
  const flipGigantic = useCallback(async () => {
    try {
      const res = await api.setToggle(GIGANTIC_TOGGLE, !giganticOn);
      setGiganticOn(res.value);
      toast(
        res.value
          ? `Gigantic category ON — volume ≥ 20,000 in³ now routes to its own lane (${GIGANTIC_TICKET})`
          : "Gigantic category OFF — baseline routing restored"
      );
    } catch (e) {
      toast(`Could not flip toggle: ${e.message}`, true);
    }
  }, [giganticOn, toast]);

  /** Send one package, animate its chip, and update counts when it lands. */
  const sendPackage = useCallback(
    async (pkg, { silent = false } = {}) => {
      let result;
      try {
        const res = await api.processOne(pkg);
        result = res.results[0];
      } catch (e) {
        toast(`Backend unreachable: ${e.message}`, true);
        return null;
      }
      const laneKey = result.status === "routed" ? result.category : "rejected";
      const lane =
        laneKey === "rejected"
          ? REJECTED
          : laneKey === "gigantic"
          ? GIGANTIC_LANE
          : LANES.find((l) => l.key === laneKey);
      const label =
        result.status === "routed"
          ? result.trackingNumber.replace(/^PKR-/, "")
          : `${result.trackingNumber.replace(/^PKR-/, "")} ✕`;

      setFlights((f) => [
        ...f,
        { id: ++chipId, category: laneKey, color: lane.color, label, result },
      ]);
      if (!silent && result.status === "rejected") {
        toast(`Rejected: ${result.reason}`, true);
      }
      return result;
    },
    [toast]
  );

  const onChipLanded = useCallback((flight) => {
    setFlights((f) => f.filter((x) => x.id !== flight.id));
    setCounts((c) => ({ ...c, [flight.category]: c[flight.category] + 1 }));
    setLanded((l) => ({ ...l, [flight.category]: Date.now() }));
    setProcessed((p) => p + 1);
  }, []);

  /** Clear everything, backend and UI. */
  const resetAll = useCallback(async () => {
    stopRef.current = true;
    setRunning(false);
    await api.reset().catch(() => {});
    setCounts(EMPTY_COUNTS);
    setLogs(EMPTY_LOGS);
    setFlights([]);
    setProcessed(0);
    setTotal(0);
    setQueueRemaining(null);
    toast("State cleared — ready for a fresh run.");
  }, [toast]);

  /** The headline act: stream all 100 sample packages through the pipeline. */
  const runAll = useCallback(async () => {
    if (running) return;
    setRunning(true);
    stopRef.current = false;
    await api.reset().catch(() => {});
    setCounts(EMPTY_COUNTS);
    setLogs(EMPTY_LOGS);
    setProcessed(0);

    let packages;
    try {
      packages = await api.samplePackages();
    } catch (e) {
      toast(`Could not load sample data: ${e.message}`, true);
      setRunning(false);
      return;
    }
    setTotal(packages.length);
    setQueueRemaining(packages.length);

    for (let i = 0; i < packages.length; i++) {
      if (stopRef.current) break;
      sendPackage(packages[i], { silent: true });
      setQueueRemaining(packages.length - i - 1);
      await sleep(BASE_INTERVAL_MS / speedRef.current);
    }

    // let the last chips land, then reconcile with backend truth
    await sleep(1100 / speedRef.current);
    if (!stopRef.current) {
      await refreshState();
      toast("Full dataset processed.");
    }
    setQueueRemaining(null);
    setRunning(false);
  }, [running, sendPackage, refreshState, toast]);

  const sendTenRandom = useCallback(async () => {
    setBuilderOpen(false);
    for (let i = 0; i < 10; i++) {
      sendPackage(randomPackage(i), { silent: true });
      await sleep(150);
    }
    setTimeout(refreshState, 2000);
  }, [sendPackage, refreshState]);

  const sendCustom = useCallback(
    async (pkg) => {
      setBuilderOpen(false);
      await sendPackage(pkg);
      setTimeout(refreshState, 1600);
    },
    [sendPackage, refreshState]
  );

  const sendChaos = useCallback(
    async (preset) => {
      await sendPackage(preset.pkg);
      setTimeout(refreshState, 1600);
    },
    [sendPackage, refreshState]
  );

  /** After a comparison run, the backend state was reset — mirror that. */
  const onComparisonDone = useCallback(() => {
    setCounts(EMPTY_COUNTS);
    setLogs(EMPTY_LOGS);
    setProcessed(0);
    setTotal(0);
  }, []);

  const throughputTotal = total || 100;
  const visibleLanes = giganticOn ? [...LANES, GIGANTIC_LANE] : LANES;
  const largeRange = giganticOn ? "8,000 – 19,999 in³" : "≥ 8,000 in³";

  return (
    <div className="shell">
      <header className="hdr">
        <div className="brand">
          <div className="mark">⧉</div>
          <div>
            <h1>Package Router</h1>
            <small>Routing test console for product owners</small>
          </div>
        </div>

        <div
          className={`feature-toggle ${giganticOn ? "on" : ""}`}
          onClick={flipGigantic}
          title="ENABLE_GIGANTIC_CATEGORY — flips routing at runtime"
        >
          <span className="ft-track">
            <span className="ft-knob" />
          </span>
          <span className="ft-label">
            Gigantic Category — {GIGANTIC_TICKET}
            <small>{giganticOn ? "ON · ≥ 20,000 in³ → Gigantic" : "OFF · baseline routing"}</small>
          </span>
        </div>

        <span className="spacer" />

        <div className="throughput">
          <span className="n mono">
            {processed}/{throughputTotal}
          </span>
          <span className="l">processed</span>
        </div>

        <div className="speed">
          <span>Speed {speed}×</span>
          <input
            type="range"
            min="0.25"
            max="4"
            step="0.25"
            value={speed}
            onChange={(e) => setSpeed(Number(e.target.value))}
          />
        </div>

        <button className="primary" onClick={runAll} disabled={running}>
          {running ? "Processing…" : "▶ Process all 100"}
        </button>
        <button onClick={() => setCompareOpen(true)} disabled={running}>
          ⇄ Before / After
        </button>
        <button className="danger" onClick={resetAll}>
          Reset
        </button>
      </header>

      <div className="workspace">
        <aside className="intake">
          <div className="card queue-card">
            <div className="card-head">
              <h3>Source queue</h3>
            </div>
            <div
              className="queue-visual"
              ref={(el) => {
                nodeRegistry.queue = el;
              }}
            >
              {Array.from({ length: Math.min(8, queueRemaining ?? 8) }).map((_, i) => (
                <div className="queue-bar" key={i} style={{ animationDelay: `${i * 0.13}s`, width: `${100 - i * 7}%` }} />
              ))}
            </div>
            <div className="queue-count">
              {queueRemaining === null ? (
                <>Sample dataset ready — <b>100</b> packages</>
              ) : (
                <><b>{queueRemaining}</b> waiting in queue</>
              )}
            </div>

            <div
              className={`processor ${running || flights.length ? "working" : ""}`}
              ref={(el) => {
                nodeRegistry.processor = el;
              }}
            >
              <div className="gear">⚙</div>
              <div>
                <div className="t1">Processor</div>
                <div className="t2">validate → measure → route</div>
              </div>
            </div>

            <div className="run-controls">
              <button onClick={() => setBuilderOpen(true)}>+ Custom package</button>
            </div>
          </div>

          <div className="card">
            <div className="card-head">
              <h3>Chaos testing</h3>
            </div>
            <div className="chaos-grid">
              {CHAOS_PRESETS.map((p) => (
                <button
                  key={p.label}
                  className={p.full ? "full" : ""}
                  onClick={() => sendChaos(p)}
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>
        </aside>

        <main className="lanes">
          {visibleLanes.map((lane) => (
            <ConsumerLane
              key={lane.key}
              lane={lane.key === "large" ? { ...lane, range: largeRange } : lane}
              count={counts[lane.key]}
              packages={logs[lane.key]}
              landedAt={landed[lane.key]}
            />
          ))}
          <ConsumerLane
            lane={REJECTED}
            count={counts.rejected}
            packages={logs.rejected}
            landedAt={landed.rejected}
            isRejected
          />
        </main>
      </div>

      <FlightLayer flights={flights} speed={speed} onLanded={onChipLanded} />

      {builderOpen && (
        <PackageBuilder
          onSend={sendCustom}
          onSendRandom={sendTenRandom}
          onClose={() => setBuilderOpen(false)}
        />
      )}

      {compareOpen && (
        <Comparison
          originalToggle={giganticOn}
          onClose={() => setCompareOpen(false)}
          onDone={onComparisonDone}
        />
      )}

      <div className="toasts">
        {toasts.map((t) => (
          <div key={t.id} className={`toast ${t.err ? "err" : ""}`}>
            {t.msg}
          </div>
        ))}
      </div>
    </div>
  );
}
