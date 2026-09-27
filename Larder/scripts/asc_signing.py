#!/usr/bin/env python3
"""Temporary App Store signing assets for CI, through the App Store Connect API.

Apple's cloud-managed signing can't provision apps that use iCloud when it's
driven by an API key, so each TestFlight build signs manually instead:

  prepare         create an Apple Distribution certificate (from a fresh key)
                  and an App Store profile for the bundle ID
  export-options  write ExportOptions for manual signing with that profile
  wait            wait for App Store Connect to finish processing a build
  cleanup         delete the profile and revoke the certificate

The certificate lives only as long as one build: `cleanup` runs even when a
step fails. Everything secret stays in the output directory on the runner and
is never printed.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY_PATH (the .p8 file).
ASC_API_BASE overrides the API address (tests).
"""

import argparse
import base64
import json
import os
import plistlib
import secrets
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID

API_BASE = os.environ.get("ASC_API_BASE", "https://api.appstoreconnect.apple.com/v1")


class APIError(Exception):
    def __init__(self, status, body):
        super().__init__(f"HTTP {status}: {body}")
        self.status = status
        self.body = body


def token():
    """A fresh 10-minute JWT for the App Store Connect API."""
    with open(os.environ["ASC_KEY_PATH"], "rb") as handle:
        key = handle.read()
    now = int(time.time())
    payload = {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    return jwt.encode(payload, key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})


def request(method, path, body=None, query=None):
    url = API_BASE + path
    if query:
        url += "?" + urllib.parse.urlencode(query)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", "Bearer " + token())
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        raise APIError(error.code, error.read().decode(errors="replace")) from None


def describe(error):
    """The API's own error titles and details, without the noise."""
    try:
        errors = json.loads(error.body).get("errors", [])
        return "; ".join(f"{e.get('title', '')}: {e.get('detail', '')}".strip(": ") for e in errors) or error.body
    except (ValueError, AttributeError):
        return str(error)


# MARK: - prepare

def make_key_and_csr():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Larder CI")])
    csr = x509.CertificateSigningRequestBuilder().subject_name(subject).sign(key, hashes.SHA256())
    return key, csr.public_bytes(serialization.Encoding.PEM).decode()


def make_p12(key, certificate_der, password):
    """A PKCS#12 bundle in the legacy (3DES/SHA-1) format the macOS keychain
    imports everywhere."""
    certificate = x509.load_der_x509_certificate(certificate_der)
    encryption = (
        serialization.PrivateFormat.PKCS12.encryption_builder()
        .kdf_rounds(50000)
        .key_cert_algorithm(pkcs12.PBES.PBESv1SHA1And3KeyTripleDESCBC)
        .hmac_hash(hashes.SHA1())
        .build(password.encode())
    )
    return pkcs12.serialize_key_and_certificates(b"Larder CI", key, certificate, None, encryption)


def bundle_id_resource(identifier):
    result = request("GET", "/bundleIds", query={"filter[identifier]": identifier, "limit": "200"})
    for item in result.get("data", []):
        if item["attributes"].get("identifier") == identifier:
            return item["id"]
    raise SystemExit(f"No App ID {identifier} in this team. Register it under Certificates, Identifiers & Profiles.")


def prepare(args):
    os.makedirs(args.out, exist_ok=True)
    state_path = os.path.join(args.out, "state.json")
    state = {}

    def save():
        with open(state_path, "w") as handle:
            json.dump(state, handle)

    key, csr_pem = make_key_and_csr()
    try:
        created = request("POST", "/certificates", {
            "data": {"type": "certificates", "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr_pem}},
        })
    except APIError as error:
        raise SystemExit(f"Couldn't create a distribution certificate: {describe(error)}")
    certificate = created["data"]
    state["certificateId"] = certificate["id"]
    save()
    print(f"Created temporary certificate {certificate['id']} (serial {certificate['attributes'].get('serialNumber')})")

    password = secrets.token_hex(16)
    der = base64.b64decode(certificate["attributes"]["certificateContent"])
    with open(os.path.join(args.out, "signing.p12"), "wb") as handle:
        handle.write(make_p12(key, der, password))
    with open(os.path.join(args.out, "p12-password"), "w") as handle:
        handle.write(password)

    bundle_id = bundle_id_resource(args.bundle_id)
    try:
        profile = request("POST", "/profiles", {
            "data": {
                "type": "profiles",
                "attributes": {"name": args.profile_name, "profileType": "IOS_APP_STORE"},
                "relationships": {
                    "bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                    "certificates": {"data": [{"type": "certificates", "id": certificate["id"]}]},
                },
            },
        })["data"]
    except APIError as error:
        raise SystemExit(f"Couldn't create an App Store profile: {describe(error)}")
    state["profileId"] = profile["id"]
    state["profileUuid"] = profile["attributes"]["uuid"]
    state["profileName"] = profile["attributes"]["name"]
    save()
    with open(os.path.join(args.out, "profile.mobileprovision"), "wb") as handle:
        handle.write(base64.b64decode(profile["attributes"]["profileContent"]))
    print(f"Created profile {state['profileName']} ({state['profileUuid']})")


# MARK: - export-options

def export_options(args):
    with open(args.state) as handle:
        state = json.load(handle)
    options = {
        "method": "app-store-connect",
        "destination": args.destination,
        "teamID": args.team_id,
        "signingStyle": "manual",
        "signingCertificate": "Apple Distribution",
        "provisioningProfiles": {args.bundle_id: state["profileUuid"]},
        "uploadSymbols": True,
        "manageAppVersionAndBuildNumber": False,
    }
    with open(args.out, "wb") as handle:
        plistlib.dump(options, handle)


# MARK: - wait

def wait(args):
    apps = request("GET", "/apps", query={"filter[bundleId]": args.bundle_id, "limit": "1"}).get("data", [])
    if not apps:
        print(f"No App Store Connect app for {args.bundle_id}; not waiting.")
        return
    deadline = time.time() + args.timeout
    state = None
    while time.time() < deadline:
        builds = request("GET", "/builds", query={
            "filter[app]": apps[0]["id"],
            "filter[version]": args.build_number,
            "limit": "5",
        }).get("data", [])
        state = builds[0]["attributes"].get("processingState") if builds else None
        if state and state != "PROCESSING":
            break
        time.sleep(30)
    print(f"Build {args.build_number}: {state or 'not visible yet'}")
    if state in ("FAILED", "INVALID"):
        raise SystemExit(f"App Store Connect marked build {args.build_number} {state}.")


# MARK: - cleanup

def cleanup(args):
    if not os.path.exists(args.state):
        print("Nothing to clean up.")
        return
    with open(args.state) as handle:
        state = json.load(handle)
    failures = []
    for kind, path in (("profile", "profileId"), ("certificate", "certificateId")):
        resource = state.get(path)
        if not resource:
            continue
        try:
            request("DELETE", f"/{kind}s/{resource}")
            print(f"{'Revoked' if kind == 'certificate' else 'Deleted'} temporary {kind} {resource}")
        except APIError as error:
            if error.status == 404:
                continue
            failures.append(f"{kind} {resource}: {describe(error)}")
    if failures:
        raise SystemExit("Cleanup failed for " + "; ".join(failures))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    p = commands.add_parser("prepare")
    p.add_argument("--out", required=True)
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--profile-name", required=True)
    p.set_defaults(run=prepare)

    p = commands.add_parser("export-options")
    p.add_argument("--state", required=True)
    p.add_argument("--destination", choices=["export", "upload"], required=True)
    p.add_argument("--team-id", required=True)
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--out", required=True)
    p.set_defaults(run=export_options)

    p = commands.add_parser("wait")
    p.add_argument("--bundle-id", required=True)
    p.add_argument("--build-number", required=True)
    p.add_argument("--timeout", type=int, default=1800)
    p.set_defaults(run=wait)

    p = commands.add_parser("cleanup")
    p.add_argument("--state", required=True)
    p.set_defaults(run=cleanup)

    args = parser.parse_args()
    args.run(args)


if __name__ == "__main__":
    sys.exit(main())
