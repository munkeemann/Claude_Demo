/**
 * Generates mock package-tracking data for the demo app.
 * Deterministic (seeded PRNG) so re-running produces the same dataset.
 *
 * Usage: node scripts/generate-mock-packages.js
 * Outputs: data/packages.json, data/packages.csv
 */

const fs = require('fs');
const path = require('path');

// ---------- seeded PRNG (mulberry32) ----------
function mulberry32(seed) {
  return function () {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const rand = mulberry32(20260708);
const pick = (arr) => arr[Math.floor(rand() * arr.length)];
const randInt = (min, max) => Math.floor(rand() * (max - min + 1)) + min;
const randFloat = (min, max, dp = 1) => +(rand() * (max - min) + min).toFixed(dp);
const chance = (p) => rand() < p;

// ---------- reference data ----------
const NOW = new Date('2026-07-08T12:00:00Z').getTime();
const HOUR = 3600 * 1000;

const CITIES = [
  { city: 'Los Angeles', state: 'CA', country: 'US', lat: 34.05, lon: -118.24, hub: true },
  { city: 'Chicago', state: 'IL', country: 'US', lat: 41.88, lon: -87.63, hub: true },
  { city: 'Memphis', state: 'TN', country: 'US', lat: 35.15, lon: -90.05, hub: true },
  { city: 'Louisville', state: 'KY', country: 'US', lat: 38.25, lon: -85.76, hub: true },
  { city: 'Dallas', state: 'TX', country: 'US', lat: 32.78, lon: -96.8, hub: true },
  { city: 'Newark', state: 'NJ', country: 'US', lat: 40.74, lon: -74.17, hub: true },
  { city: 'Atlanta', state: 'GA', country: 'US', lat: 33.75, lon: -84.39, hub: true },
  { city: 'Seattle', state: 'WA', country: 'US', lat: 47.61, lon: -122.33 },
  { city: 'Denver', state: 'CO', country: 'US', lat: 39.74, lon: -104.99 },
  { city: 'Phoenix', state: 'AZ', country: 'US', lat: 33.45, lon: -112.07 },
  { city: 'Miami', state: 'FL', country: 'US', lat: 25.76, lon: -80.19 },
  { city: 'Boston', state: 'MA', country: 'US', lat: 42.36, lon: -71.06 },
  { city: 'Minneapolis', state: 'MN', country: 'US', lat: 44.98, lon: -93.27 },
  { city: 'Portland', state: 'OR', country: 'US', lat: 45.52, lon: -122.68 },
  { city: 'Nashville', state: 'TN', country: 'US', lat: 36.16, lon: -86.78 },
  { city: 'Salt Lake City', state: 'UT', country: 'US', lat: 40.76, lon: -111.89 },
  { city: 'Kansas City', state: 'MO', country: 'US', lat: 39.1, lon: -94.58 },
  { city: 'Columbus', state: 'OH', country: 'US', lat: 39.96, lon: -83.0 },
  { city: 'San Diego', state: 'CA', country: 'US', lat: 32.72, lon: -117.16 },
  { city: 'Austin', state: 'TX', country: 'US', lat: 30.27, lon: -97.74 },
  { city: 'Toronto', state: 'ON', country: 'CA', lat: 43.65, lon: -79.38 },
  { city: 'Vancouver', state: 'BC', country: 'CA', lat: 49.28, lon: -123.12 },
  { city: 'London', state: '', country: 'GB', lat: 51.51, lon: -0.13 },
  { city: 'Frankfurt', state: '', country: 'DE', lat: 50.11, lon: 8.68 },
  { city: 'Tokyo', state: '', country: 'JP', lat: 35.68, lon: 139.69 },
  { city: 'Shenzhen', state: '', country: 'CN', lat: 22.54, lon: 114.06 },
];
const HUBS = CITIES.filter((c) => c.hub);

const CARRIERS = [
  { name: 'SwiftShip', prefix: 'SS', digits: 12 },
  { name: 'Meteor Express', prefix: 'MX', digits: 10 },
  { name: 'NorthStar Logistics', prefix: 'NS', digits: 11 },
  { name: 'GlobalParcel', prefix: 'GP', digits: 12 },
];

const SERVICES = [
  { level: 'Economy', speedH: [96, 168] },
  { level: 'Standard', speedH: [72, 120] },
  { level: 'Express', speedH: [36, 60] },
  { level: 'Overnight', speedH: [18, 28] },
];

const FIRST = ['James', 'Maria', 'Wei', 'Aisha', 'Liam', 'Sofia', 'Noah', 'Emma', 'Raj', 'Yuki', 'Carlos', 'Fatima', 'Ethan', 'Olivia', 'Marcus', 'Priya', 'Diego', 'Hannah', 'Kwame', 'Elena'];
const LAST = ['Smith', 'Garcia', 'Chen', 'Johnson', 'Patel', 'Kim', 'Brown', 'Nguyen', 'Muller', 'Rossi', 'Silva', 'Kowalski', 'Tanaka', 'Okafor', 'Larsen', 'Dubois', 'Ivanov', 'Martinez', 'Lee', 'Walker'];
const COMPANIES = ['Acme Supply Co.', 'Blue Harbor Goods', 'Pinnacle Parts', 'Verdant Botanics', 'Nova Electronics', 'Hearthstone Home', 'Cascade Outfitters', 'Lumen Labs', 'Redwood Books', 'Atlas Tools', null, null, null];
const CONTENTS = ['Electronics', 'Apparel', 'Books & Media', 'Home Goods', 'Auto Parts', 'Toys & Games', 'Health & Beauty', 'Sporting Goods', 'Documents', 'Machinery Parts'];

const EXCEPTIONS = [
  { code: 'WEATHER_DELAY', desc: 'Delivery delayed due to severe weather conditions' },
  { code: 'ADDRESS_ISSUE', desc: 'Incorrect or incomplete delivery address — action required' },
  { code: 'CUSTOMS_HOLD', desc: 'Held in customs — awaiting documentation' },
  { code: 'DAMAGED', desc: 'Package damaged in handling — under review' },
  { code: 'MISSED_CONNECTION', desc: 'Missed line-haul connection — rebooked on next departure' },
];

// status mix: index i of 100 determines final status
function finalStatusFor(i) {
  if (i < 42) return 'DELIVERED';
  if (i < 72) return 'IN_TRANSIT';
  if (i < 82) return 'OUT_FOR_DELIVERY';
  if (i < 90) return 'EXCEPTION';
  if (i < 95) return 'LABEL_CREATED';
  return 'RETURNED';
}

const personName = () => `${pick(FIRST)} ${pick(LAST)}`;
const facilityFor = (c, kind) =>
  kind === 'hub' ? `${c.city} Regional Hub` : `${c.city} Sort Facility`;
const iso = (t) => new Date(t).toISOString();

function buildRoute(origin, destination) {
  const nHubs = origin.country !== destination.country ? randInt(2, 3) : randInt(1, 2);
  const hubs = [];
  const pool = HUBS.filter((h) => h !== origin && h !== destination);
  while (hubs.length < nHubs) {
    const h = pick(pool);
    if (!hubs.includes(h)) hubs.push(h);
  }
  return [origin, ...hubs, destination];
}

function generatePackage(i) {
  const carrier = pick(CARRIERS);
  const service = pick(SERVICES);
  const finalStatus = finalStatusFor(i);
  const international = chance(0.18);

  let origin = pick(CITIES);
  let destination = pick(CITIES.filter((c) => c !== origin));
  if (!international) {
    origin = pick(CITIES.filter((c) => c.country === 'US'));
    destination = pick(CITIES.filter((c) => c.country === 'US' && c !== origin));
  }

  const trackingId = `${carrier.prefix}${String(randInt(0, 10 ** carrier.digits - 1)).padStart(carrier.digits, '0')}`;

  // transit window
  const transitH = randInt(service.speedH[0], service.speedH[1]);
  // ship date: delivered ones shipped further back; pending ones recently
  let shippedAt;
  if (finalStatus === 'DELIVERED' || finalStatus === 'RETURNED') {
    shippedAt = NOW - randInt(transitH + 24, transitH + 24 * 14) * HOUR;
  } else if (finalStatus === 'LABEL_CREATED') {
    shippedAt = NOW + randInt(4, 48) * HOUR; // pickup scheduled in the future
  } else {
    shippedAt = NOW - randInt(6, transitH - 4) * HOUR;
  }
  const estimatedDelivery = shippedAt + transitH * HOUR;

  const route = buildRoute(origin, destination);

  // itinerary legs with planned times spread across the transit window
  const legs = [];
  for (let l = 0; l < route.length - 1; l++) {
    const t0 = shippedAt + ((l + 0.15) / (route.length - 1)) * transitH * HOUR;
    const t1 = shippedAt + ((l + 0.85) / (route.length - 1)) * transitH * HOUR;
    const intl = route[l].country !== route[l + 1].country;
    legs.push({
      leg: l + 1,
      from: `${route[l].city}, ${route[l].state || route[l].country}`,
      to: `${route[l + 1].city}, ${route[l + 1].state || route[l + 1].country}`,
      mode: intl ? 'air' : service.level === 'Overnight' || service.level === 'Express' ? pick(['air', 'air', 'truck']) : pick(['truck', 'truck', 'rail', 'air']),
      plannedDeparture: iso(t0),
      plannedArrival: iso(t1),
    });
  }

  // ---------- scan events ----------
  const events = [];
  const addEvent = (t, c, code, desc, facility) =>
    events.push({
      timestamp: iso(t),
      status: code,
      description: desc,
      facility: facility || facilityFor(c, c.hub ? 'hub' : 'local'),
      city: c.city,
      state: c.state,
      country: c.country,
      lat: c.lat,
      lon: c.lon,
    });

  const labelAt = shippedAt - randInt(6, 36) * HOUR;
  addEvent(labelAt, origin, 'LABEL_CREATED', 'Shipping label created; carrier awaiting package', 'Shipper facility');

  let exception = null;

  if (finalStatus !== 'LABEL_CREATED') {
    addEvent(shippedAt, origin, 'PICKED_UP', 'Package picked up by carrier');

    // how far along the route the package is
    const progress =
      finalStatus === 'DELIVERED' || finalStatus === 'RETURNED'
        ? 1
        : finalStatus === 'OUT_FOR_DELIVERY'
        ? 0.98
        : rand() * 0.6 + 0.25; // in transit / exception: 25–85%

    const lastNode = Math.max(1, Math.floor(progress * (route.length - 1)));
    for (let n = 1; n <= lastNode; n++) {
      const c = route[n];
      const tArr = shippedAt + (n / (route.length - 1)) * transitH * HOUR * 0.9 + randInt(-3, 3) * HOUR;
      addEvent(tArr, c, 'ARRIVED_AT_FACILITY', `Arrived at ${c.city} facility`);
      if (route[n - 1].country !== c.country && c === destination === false) {
        addEvent(tArr + 2 * HOUR, c, 'CUSTOMS_CLEARED', 'International shipment cleared customs');
      }
      if (n < lastNode || finalStatus === 'DELIVERED' || finalStatus === 'RETURNED' || finalStatus === 'OUT_FOR_DELIVERY') {
        addEvent(tArr + randInt(2, 8) * HOUR, c, 'DEPARTED_FACILITY', `Departed ${c.city} facility`);
      }
    }

    // terminal events must come after every facility scan
    const lastFacilityT = Math.max(...events.map((e) => Date.parse(e.timestamp)));

    if (finalStatus === 'OUT_FOR_DELIVERY') {
      addEvent(Math.max(NOW - randInt(1, 5) * HOUR, lastFacilityT + HOUR), destination, 'OUT_FOR_DELIVERY', 'On vehicle for delivery');
    }

    if (finalStatus === 'DELIVERED') {
      const dAt = Math.max(estimatedDelivery + randInt(-8, 6) * HOUR, lastFacilityT + 8 * HOUR);
      addEvent(dAt - 6 * HOUR, destination, 'OUT_FOR_DELIVERY', 'On vehicle for delivery');
      if (chance(0.15)) {
        addEvent(dAt - 3 * HOUR, destination, 'DELIVERY_ATTEMPTED', 'Delivery attempted — no one available; will retry');
      }
      addEvent(dAt, destination, 'DELIVERED', `Delivered — ${pick(['left at front door', 'handed to resident', 'left with receptionist', 'placed in parcel locker', 'signed for by recipient'])}`);
    }

    if (finalStatus === 'EXCEPTION') {
      exception = international ? pick(EXCEPTIONS) : pick(EXCEPTIONS.filter((e) => e.code !== 'CUSTOMS_HOLD'));
      const c = route[lastNode];
      addEvent(Math.max(NOW - randInt(2, 24) * HOUR, lastFacilityT + HOUR), c, exception.code, exception.desc);
    }

    if (finalStatus === 'RETURNED') {
      const c = destination;
      const base = Math.max(estimatedDelivery, lastFacilityT + 6 * HOUR);
      addEvent(base, c, 'DELIVERY_ATTEMPTED', 'Delivery attempted — address inaccessible');
      addEvent(base + 24 * HOUR, c, 'DELIVERY_ATTEMPTED', 'Second delivery attempt failed');
      addEvent(base + 30 * HOUR, c, 'RETURN_TO_SENDER', 'Undeliverable — returning to sender');
      addEvent(base + randInt(72, 120) * HOUR, origin, 'RETURNED', 'Package returned to shipper');
    }
  }

  events.sort((a, b) => a.timestamp.localeCompare(b.timestamp));
  const lastEvent = events[events.length - 1];

  const deliveredEvent = events.find((e) => e.status === 'DELIVERED');
  const weightKg = randFloat(0.2, 28, 2);

  return {
    trackingId,
    carrier: carrier.name,
    serviceLevel: service.level,
    status: finalStatus,
    statusDescription: lastEvent.description,
    shippedAt: iso(shippedAt),
    estimatedDelivery: iso(estimatedDelivery),
    deliveredAt: deliveredEvent ? deliveredEvent.timestamp : null,
    international,
    sender: { name: personName(), company: pick(COMPANIES) },
    recipient: { name: personName() },
    origin: { city: origin.city, state: origin.state, country: origin.country, lat: origin.lat, lon: origin.lon },
    destination: { city: destination.city, state: destination.state, country: destination.country, lat: destination.lat, lon: destination.lon },
    package: {
      weightKg,
      dimensionsCm: { length: randInt(10, 120), width: randInt(8, 80), height: randInt(4, 60) },
      declaredValueUSD: randInt(10, 2500),
      contentsCategory: pick(CONTENTS),
      fragile: chance(0.2),
      signatureRequired: chance(0.25),
      pieces: chance(0.85) ? 1 : randInt(2, 4),
    },
    exception: exception ? { code: exception.code, description: exception.desc } : null,
    currentLocation: { city: lastEvent.city, state: lastEvent.state, country: lastEvent.country, lat: lastEvent.lat, lon: lastEvent.lon },
    itinerary: legs,
    scanEvents: events,
  };
}

// ---------- generate ----------
const packages = [];
for (let i = 0; i < 100; i++) packages.push(generatePackage(i));

const outDir = path.join(__dirname, '..', 'data');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'packages.json'), JSON.stringify(packages, null, 2));

// flat CSV summary table
const csvRows = [
  'trackingId,carrier,serviceLevel,status,shippedAt,estimatedDelivery,deliveredAt,originCity,originCountry,destCity,destCountry,currentCity,weightKg,lengthCm,widthCm,heightCm,declaredValueUSD,contents,fragile,signatureRequired,international,numScanEvents,exceptionCode',
];
for (const p of packages) {
  csvRows.push(
    [
      p.trackingId, p.carrier, p.serviceLevel, p.status, p.shippedAt, p.estimatedDelivery,
      p.deliveredAt || '', p.origin.city, p.origin.country, p.destination.city, p.destination.country,
      p.currentLocation.city, p.package.weightKg, p.package.dimensionsCm.length, p.package.dimensionsCm.width,
      p.package.dimensionsCm.height, p.package.declaredValueUSD, p.package.contentsCategory,
      p.package.fragile, p.package.signatureRequired, p.international, p.scanEvents.length,
      p.exception ? p.exception.code : '',
    ].map((v) => (String(v).includes(',') ? `"${v}"` : v)).join(','),
  );
}
fs.writeFileSync(path.join(outDir, 'packages.csv'), csvRows.join('\n'));

// browser-friendly copy for the demo app (loads via <script src> under file://)
fs.writeFileSync(
  path.join(outDir, 'packages.js'),
  'window.PACKAGES = ' + JSON.stringify(packages) + ';\n',
);

// console summary
const byStatus = {};
for (const p of packages) byStatus[p.status] = (byStatus[p.status] || 0) + 1;
console.log(`Generated ${packages.length} packages -> data/packages.json, data/packages.csv`);
console.log('Status mix:', JSON.stringify(byStatus));
console.log('Total scan events:', packages.reduce((s, p) => s + p.scanEvents.length, 0));

// rebuild the self-contained app so index.html carries the fresh data
if (fs.existsSync(path.join(__dirname, 'build-app.js'))) {
  require('./build-app.js');
}
