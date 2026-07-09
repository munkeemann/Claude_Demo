/**
 * "Move to L3" release-notification generator.
 *
 * Reads release.json (which stories + deploy metadata) and jira/stories.json
 * (the backlog source of truth) and emits, for the stories being promoted:
 *   - out/email-draft.html   stakeholder release email (rich)
 *   - out/email-draft.md     same, markdown
 *   - out/teams-message.md   concise Teams message (posted live into the app)
 *   - out/change-request.md  mocked change request
 *   - out/deployment-rows.json  data handed to the Excel step
 *
 * Then invokes build-xlsx.py to write deployment-log.xlsx.
 *
 * One input (release.json) drives every output — edit it, re-run this, and
 * the email, Teams message, change request, and Excel log all update together.
 *
 * Usage: node release/scripts/generate-release.js
 */

const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const RELEASE_DIR = path.join(__dirname, "..");
const OUT_DIR = path.join(RELEASE_DIR, "out");
const release = JSON.parse(fs.readFileSync(path.join(RELEASE_DIR, "release.json"), "utf8"));
const backlog = JSON.parse(fs.readFileSync(path.join(RELEASE_DIR, "jira", "stories.json"), "utf8"));

const SITE = backlog.jira.site;
const byKey = {};
backlog.stories.forEach((s) => (byKey[s.key] = s));
backlog.features.forEach((f) => (byKey[f.key] = f));

// resolve selected stories (preserve release.json order, skip unknown keys with a warning)
const stories = [];
release.storyKeys.forEach((k) => {
  if (byKey[k] && byKey[k].ref[0] === "S") stories.push(byKey[k]);
  else console.warn("  ! release.json references unknown/non-story key: " + k);
});

const totalPoints = stories.reduce((n, s) => n + (s.storyPoints || 0), 0);
const crNumber = "CHG-" + release.deployDate.replace(/-/g, "").slice(0, 4) + "-" + release.deployDate.replace(/-/g, "").slice(4);
const deployPretty = new Date(release.deployDate + "T00:00:00").toLocaleDateString(undefined, {
  weekday: "long", month: "long", day: "numeric", year: "numeric",
});

// features touched by this release
const featureRefs = [...new Set(stories.map((s) => s.feature))];
const features = featureRefs.map((r) => backlog.features.find((f) => f.ref === r)).filter(Boolean);

function issueUrl(key) { return SITE + "/browse/" + key; }

// ---------- change request ----------
function changeRequestMd() {
  return `# Change Request ${crNumber}

| Field | Value |
|---|---|
| **CR number** | ${crNumber} |
| **Title** | Promote ${release.releaseName} to ${release.environment} (${release.environmentName}) |
| **Environment** | ${release.environment} — ${release.environmentName} |
| **Scheduled** | ${deployPretty}, ${release.deployWindow} |
| **Deployed by** | ${release.deployedBy} |
| **Approver** | ${release.approver} |
| **Risk level** | ${release.riskLevel} |
| **Affected components** | ${release.components.join(", ")} |
| **Story count** | ${stories.length} (${totalPoints} points) |

## Scope
Promotion of the following stories from L2 (QA/Staging) to ${release.environment} (${release.environmentName}):

${stories.map((s) => `- **${s.key}** — ${s.summary} (${s.storyPoints} pts)`).join("\n")}

## Rollback plan
${release.rollbackPlan}

## Backout trigger
Any P1/P2 defect in ${release.components.join(" or ")} within the first 60 minutes post-deploy, or error rate above baseline.

---
*Generated from release.json + jira/stories.json. CR number derived from deploy date.*
`;
}

// ---------- email ----------
function storyBusinessBullets() {
  return stories.map((s) => `- **${s.summary}** (${s.key}) — ${s.businessValue}`).join("\n");
}
function storyTechBullets() {
  return stories.map((s) => `- **${s.key}** — ${s.techNotes}`).join("\n");
}

function emailMd() {
  return `**Subject:** [Release] ${release.releaseName} → ${release.environment} (${release.environmentName}) — ${deployPretty}

Hi all,

**${release.releaseName}** is scheduled to promote to **${release.environment} (${release.environmentName})** on **${deployPretty}**, during the **${release.deployWindow}** window. This release moves **${stories.length} stories (${totalPoints} points)** across ${features.length} feature area${features.length === 1 ? "" : "s"}: ${features.map((f) => f.summary).join(", ")}.

### Why it matters (business value)
${storyBusinessBullets()}

### What's changing (technical summary)
${storyTechBullets()}

### Deployment
- **Environment:** ${release.environment} — ${release.environmentName}
- **Window:** ${deployPretty}, ${release.deployWindow}
- **Deployed by:** ${release.deployedBy}
- **Approver:** ${release.approver}
- **Risk:** ${release.riskLevel}
- **Change request:** ${crNumber}
- **Components:** ${release.components.join(", ")}

### Rollback
${release.rollbackPlan}

Tracking in Jira: ${stories.map((s) => s.key).join(", ")}.

Thanks,
${release.deployedBy}
`;
}

function emailHtml() {
  const row = (label, val) =>
    `<tr><td style="padding:4px 12px 4px 0;color:#64748b;white-space:nowrap">${label}</td><td style="padding:4px 0;color:#0f172a"><b>${val}</b></td></tr>`;
  const bizItems = stories.map((s) =>
    `<li style="margin:6px 0"><b>${esc(s.summary)}</b> <span style="color:#64748b">(${s.key})</span><br><span style="color:#334155">${esc(s.businessValue)}</span></li>`).join("");
  const techItems = stories.map((s) =>
    `<li style="margin:5px 0"><b>${s.key}</b> — <span style="color:#334155">${esc(s.techNotes)}</span></li>`).join("");
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0"></head><body style="margin:0;background:#f1f5f9;font-family:Segoe UI,Arial,sans-serif;color:#0f172a">
<div style="max-width:680px;margin:0 auto;padding:24px">
  <div style="background:linear-gradient(135deg,#0ea5e9,#06b6d4);border-radius:14px 14px 0 0;padding:22px 26px;color:#fff">
    <div style="font-size:13px;opacity:.9;letter-spacing:.5px">RELEASE NOTIFICATION</div>
    <div style="font-size:22px;font-weight:700;margin-top:4px">${esc(release.releaseName)} → ${release.environment} (${esc(release.environmentName)})</div>
    <div style="font-size:14px;opacity:.95;margin-top:4px">${deployPretty} · ${esc(release.deployWindow)}</div>
  </div>
  <div style="background:#fff;border:1px solid #e2e8f0;border-top:none;border-radius:0 0 14px 14px;padding:24px 26px">
    <p style="margin:0 0 16px">Hi all — <b>${esc(release.releaseName)}</b> is scheduled to promote to <b>${release.environment} (${esc(release.environmentName)})</b>. This release moves <b>${stories.length} stories (${totalPoints} points)</b> across ${features.length} feature area${features.length === 1 ? "" : "s"}.</p>

    <h3 style="margin:18px 0 8px;font-size:14px;text-transform:uppercase;letter-spacing:.6px;color:#0891b2">Why it matters</h3>
    <ul style="margin:0;padding-left:20px">${bizItems}</ul>

    <h3 style="margin:20px 0 8px;font-size:14px;text-transform:uppercase;letter-spacing:.6px;color:#0891b2">What's changing</h3>
    <ul style="margin:0;padding-left:20px">${techItems}</ul>

    <h3 style="margin:20px 0 8px;font-size:14px;text-transform:uppercase;letter-spacing:.6px;color:#0891b2">Deployment</h3>
    <table style="border-collapse:collapse;font-size:14px">
      ${row("Environment", release.environment + " — " + esc(release.environmentName))}
      ${row("Window", deployPretty + ", " + esc(release.deployWindow))}
      ${row("Deployed by", esc(release.deployedBy))}
      ${row("Approver", esc(release.approver))}
      ${row("Risk", esc(release.riskLevel))}
      ${row("Change request", crNumber)}
      ${row("Components", esc(release.components.join(", ")))}
    </table>

    <h3 style="margin:20px 0 8px;font-size:14px;text-transform:uppercase;letter-spacing:.6px;color:#0891b2">Rollback</h3>
    <p style="margin:0;color:#334155">${esc(release.rollbackPlan)}</p>

    <p style="margin:18px 0 0;color:#64748b;font-size:13px">Tracking in Jira: ${stories.map((s) => `<a href="${issueUrl(s.key)}" style="color:#0891b2">${s.key}</a>`).join(", ")}</p>
  </div>
  <div style="text-align:center;color:#94a3b8;font-size:12px;padding:14px">Generated from release.json — ParcelTrace release automation</div>
</div>
</body></html>`;
}

// ---------- teams ----------
function teamsMd() {
  const recipients = (release.audience && release.audience.recipients) || [];
  const toLine = recipients.length
    ? "To: " + recipients.map((r) => "@" + r.replace(/ \(.*\)$/, "")).join("  ") + "\n\n"
    : "";
  return `${toLine}📦 **${release.releaseName} — Promotion to ${release.environment} (${release.environmentName})**

Scheduled: **${deployPretty}, ${release.deployWindow}** · Change request **${crNumber}** · Risk: ${release.riskLevel}

**Shipping ${stories.length} stories (${totalPoints} pts):**
${stories.map((s) => `• ${s.summary} (${s.key})`).join("\n")}

Deployed by ${release.deployedBy}. Full business value + technical details in the release email. Questions → reply here.`;
}

function esc(s) {
  return String(s == null ? "" : s).replace(/[&<>]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
}

// ---------- deployment rows for Excel ----------
function deploymentRows() {
  return {
    release: release.releaseName,
    generatedFrom: "release.json",
    rows: stories.map((s) => ({
      release: release.releaseName,
      story: s.key,
      summary: s.summary,
      feature: (backlog.features.find((f) => f.ref === s.feature) || {}).summary || "",
      environment: release.environment + " (" + release.environmentName + ")",
      deployDate: release.deployDate,
      deployWindow: release.deployWindow,
      deployedBy: release.deployedBy,
      approver: release.approver,
      changeRequest: crNumber,
      riskLevel: release.riskLevel,
      storyPoints: s.storyPoints,
      status: "Scheduled",
    })),
  };
}

// ---------- write ----------
fs.mkdirSync(OUT_DIR, { recursive: true });
fs.writeFileSync(path.join(OUT_DIR, "change-request.md"), changeRequestMd());
fs.writeFileSync(path.join(OUT_DIR, "email-draft.md"), emailMd());
fs.writeFileSync(path.join(OUT_DIR, "email-draft.html"), emailHtml());
fs.writeFileSync(path.join(OUT_DIR, "teams-message.md"), teamsMd());
fs.writeFileSync(path.join(OUT_DIR, "deployment-rows.json"), JSON.stringify(deploymentRows(), null, 2));

console.log("Release: " + release.releaseName + " → " + release.environment + " (" + release.environmentName + ")");
console.log("Stories: " + stories.map((s) => s.key).join(", ") + "  (" + totalPoints + " pts)");
console.log("Change request: " + crNumber + "  ·  Deploy: " + release.deployDate + " " + release.deployWindow);
console.log("Wrote: out/email-draft.html, out/email-draft.md, out/teams-message.md, out/change-request.md, out/deployment-rows.json");

// ---------- Excel step ----------
const py = spawnSync("python", [path.join(__dirname, "build-xlsx.py")], { encoding: "utf8" });
if (py.status === 0) {
  process.stdout.write(py.stdout);
} else {
  console.warn("  ! Excel step skipped (python/openpyxl issue):\n" + (py.stderr || py.error));
  console.warn("  Run manually: python release/scripts/build-xlsx.py");
}
