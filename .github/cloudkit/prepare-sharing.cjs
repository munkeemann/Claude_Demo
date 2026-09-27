// Adds the record type CloudKit uses for shares (`cloudkit.share`) to
// Larder's Development schema, so it can be deployed to Production.
//
// CloudKit creates that type the first time a share is saved in the
// Development environment, and TestFlight builds only ever talk to
// Production, so it's done here instead:
//   1. With a management token: import the Development schema plus the
//      share type (validated first).
//   2. With a user token as well: save a real zone-wide share in a scratch
//      zone of the Development private database, which is exactly what
//      makes CloudKit create the type.
// Then Deploy Schema Changes in CloudKit Console copies it to Production.

const { CKEnvironment, PromisesApi } = require("@apple/cktool.database");
const { File, createConfiguration } = require("@apple/cktool.target.nodejs");

const teamId = "NX8A5B7T82";
const containerId = "iCloud.com.munkeemann.larder";
const configuration = createConfiguration();
const managementToken = process.env.CLOUDKIT_MANAGEMENT_TOKEN;
const userToken = process.env.CLOUDKIT_USER_TOKEN;

const describe = (error) => {
  try {
    return configuration.jsonStringify(error, null, 2);
  } catch {
    return String(error);
  }
};

const shareTypeVariants = [
  `
    RECORD TYPE cloudkit.share (
        "___createTime" TIMESTAMP,
        "___createdBy"  REFERENCE,
        "___etag"       STRING,
        "___modTime"    TIMESTAMP,
        "___modifiedBy" REFERENCE,
        "___recordID"   REFERENCE QUERYABLE,
        GRANT WRITE TO "_creator",
        GRANT CREATE TO "_icloud",
        GRANT READ TO "_world"
    );
`,
  `
    RECORD TYPE "cloudkit.share" (
        "___createTime" TIMESTAMP,
        "___createdBy"  REFERENCE,
        "___etag"       STRING,
        "___modTime"    TIMESTAMP,
        "___modifiedBy" REFERENCE,
        "___recordID"   REFERENCE QUERYABLE,
        GRANT WRITE TO "_creator",
        GRANT CREATE TO "_icloud",
        GRANT READ TO "_world"
    );
`,
];

async function exportSchema(api, environment) {
  const response = await api.exportSchema({ teamId, containerId, environment });
  return await response.result.text();
}

async function viaImport() {
  const api = new PromisesApi({ configuration, security: { ManagementTokenAuth: managementToken } });
  const production = await exportSchema(api, CKEnvironment.PRODUCTION);
  console.log("::group::Production schema now");
  console.log(production);
  console.log("::endgroup::");
  const development = await exportSchema(api, CKEnvironment.DEVELOPMENT);
  console.log("::group::Development schema now");
  console.log(development);
  console.log("::endgroup::");
  if (/cloudkit\.share/.test(development)) {
    console.log("Development already has cloudkit.share.");
    return true;
  }

  for (const [index, variant] of shareTypeVariants.entries()) {
    const text = development.trimEnd() + "\n" + variant;
    const file = () => new File([Buffer.from(text)], "schema.ckdb");
    try {
      await api.validateSchema({ teamId, containerId, environment: CKEnvironment.DEVELOPMENT, file: file() });
      console.log(`Variant ${index + 1} validates; importing.`);
      await api.importSchema({ teamId, containerId, environment: CKEnvironment.DEVELOPMENT, file: file() });
      const after = await exportSchema(api, CKEnvironment.DEVELOPMENT);
      if (/cloudkit\.share/.test(after)) {
        console.log("Imported: Development now has cloudkit.share.");
        return true;
      }
      console.log("Import accepted, but cloudkit.share isn't in the exported schema yet.");
    } catch (error) {
      console.log(`Variant ${index + 1} was rejected:\n${describe(error)}`);
    }
  }
  return false;
}

async function viaShare() {
  const api = new PromisesApi({ configuration, security: { UserTokenAuth: userToken } });
  const where = { containerId, environment: CKEnvironment.DEVELOPMENT, databaseType: "private" };
  const zoneName = "LarderSchemaSetup";
  try {
    await api.createZone({ ...where, body: { zoneName } });
    console.log(`Created zone ${zoneName} in the Development private database.`);
  } catch (error) {
    console.log(`Creating the zone failed (it may already exist):\n${describe(error)}`);
  }
  try {
    await api.createRecord({
      ...where,
      zoneName,
      body: { recordType: "cloudkit.share", recordName: "cloudkit.zoneshare", createShortGuid: true, fields: {} },
    });
    console.log("Saved a zone-wide share in Development.");
    return true;
  } catch (error) {
    console.log(`Saving the share failed:\n${describe(error)}`);
    return false;
  }
}

(async () => {
  if (!managementToken) {
    console.log("::error::Add the CLOUDKIT_MANAGEMENT_TOKEN repository secret (CloudKit Console home → account menu → Manage Tokens; it is account-wide, not under a container).");
    process.exit(1);
  }
  let ready = await viaImport();
  if (!ready && userToken) {
    ready = await viaShare();
  }
  if (!ready) {
    console.log("::error::Couldn't add cloudkit.share to the Development schema.");
    process.exit(1);
  }
  console.log("Done. In CloudKit Console → Development → Deploy Schema Changes to Production.");
})().catch((error) => {
  console.log(`::error::${describe(error)}`);
  process.exit(1);
});
