import { useState } from "react";

/**
 * Custom package builder — all 20 fields, dimensions front and center.
 * Deliberately performs NO client-side validation: the demo's point is
 * that the backend handles whatever gets thrown at it.
 */

const DEFAULTS = {
  trackingNumber: "PKR-CUSTOM-0001",
  lengthIn: "12",
  widthIn: "9",
  heightIn: "6",
  weightLbs: "4.2",
  serviceType: "Ground",
  originCity: "Seattle",
  originZip: "98101",
  destinationCity: "Chicago",
  destinationZip: "60601",
  declaredValue: "120",
  shipDate: "2026-07-09",
  estimatedDelivery: "2026-07-14",
  senderName: "Avery Chen",
  recipientName: "Jordan Reyes",
  hazmatFlag: "false",
  signatureRequired: "false",
  residentialFlag: "true",
  priorityScore: "50",
  contentsDescription: "Consumer electronics",
};

// Convert a raw form string to what the API receives. Numeric-looking
// text becomes a number; empty becomes null (a *missing* value); other
// text passes through as-is so the backend's validator gets to judge it.
function coerce(value) {
  if (value === "") return null;
  if (value === "true") return true;
  if (value === "false") return false;
  const n = Number(value);
  return Number.isNaN(n) ? value : n;
}

const CITY_POOL = ["Seattle", "Denver", "Austin", "Boston", "Miami", "Chicago", "Phoenix"];

export function randomPackage(i) {
  const r = (a, b) => Math.round(a + Math.random() * (b - a));
  return {
    ...Object.fromEntries(Object.entries(DEFAULTS).map(([k, v]) => [k, coerce(v)])),
    trackingNumber: `PKR-RAND-${String(Date.now() % 100000).padStart(5, "0")}-${i}`,
    lengthIn: r(4, 45),
    widthIn: r(3, 32),
    heightIn: r(2, 26),
    weightLbs: r(1, 80),
    originCity: CITY_POOL[r(0, CITY_POOL.length - 1)],
    destinationCity: CITY_POOL[r(0, CITY_POOL.length - 1)],
    priorityScore: r(1, 100),
  };
}

export default function PackageBuilder({ onSend, onSendRandom, onClose }) {
  const [form, setForm] = useState(DEFAULTS);
  const set = (k) => (e) => setForm({ ...form, [k]: e.target.value });

  const submit = () => {
    onSend(Object.fromEntries(Object.entries(form).map(([k, v]) => [k, coerce(v)])));
  };

  const dimField = (key, label) => (
    <div className="field">
      <label>{label}</label>
      <input value={form[key]} onChange={set(key)} />
    </div>
  );

  const field = (key, label) => (
    <div className="field">
      <label>{label}</label>
      <input value={form[key]} onChange={set(key)} />
    </div>
  );

  return (
    <div className="modal-veil" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h2>Custom package</h2>
        <div className="sub">
          All 20 fields are editable and nothing is validated client-side — send bad data on
          purpose and watch the router handle it.
        </div>

        <div className="dims-row">
          {dimField("lengthIn", "Length (in)")}
          {dimField("widthIn", "Width (in)")}
          {dimField("heightIn", "Height (in)")}
        </div>

        <div className="form-grid">
          {field("trackingNumber", "Tracking #")}
          {field("weightLbs", "Weight (lbs)")}
          {field("serviceType", "Service type")}
          {field("declaredValue", "Declared value $")}
          {field("originCity", "Origin city")}
          {field("originZip", "Origin ZIP")}
          {field("destinationCity", "Destination city")}
          {field("destinationZip", "Destination ZIP")}
          {field("shipDate", "Ship date")}
          {field("estimatedDelivery", "Est. delivery")}
          {field("senderName", "Sender")}
          {field("recipientName", "Recipient")}
          {field("hazmatFlag", "Hazmat")}
          {field("signatureRequired", "Signature req.")}
          {field("residentialFlag", "Residential")}
          {field("priorityScore", "Priority score")}
          {field("contentsDescription", "Contents")}
        </div>

        <div className="modal-actions">
          <button className="ghost" onClick={onClose}>Close</button>
          <button onClick={onSendRandom}>Send 10 random</button>
          <button className="primary" onClick={submit}>Send package</button>
        </div>
      </div>
    </div>
  );
}
