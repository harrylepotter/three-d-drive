"""Write private Xcode build settings shared by the app and widget."""
import argparse
import ipaddress
import plistlib
import re
from pathlib import Path
from urllib.parse import urlsplit

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("origin", help="Home Assistant origin, including the scheme and optional port")
parser.add_argument("bundle_id", help="Your app's registered bundle identifier")
parser.add_argument("--team", help="Apple Developer team ID")
args = parser.parse_args()
url = urlsplit(args.origin)
if (url.scheme not in {"http", "https"} or not url.hostname or url.username is not None
        or url.password is not None or url.path not in {"", "/"} or url.query or url.fragment):
    parser.error("Supply an HTTP or HTTPS origin with no credentials, query, or path.")
host = url.hostname
try:
    ipaddress.ip_address(host)
except ValueError:
    if not re.fullmatch(r"[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?", host):
        parser.error("Invalid host.")
if not re.fullmatch(r"[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+", args.bundle_id):
    parser.error("Invalid bundle identifier.")
if args.team and not re.fullmatch(r"[A-Z0-9]{10}", args.team):
    parser.error("Invalid team ID.")
try:
    port = url.port if url.port is not None else (443 if url.scheme == "https" else 80)
except ValueError as error:
    parser.error(str(error))
if port == 0:
    parser.error("Port must be between 1 and 65535.")

config = Path(__file__).resolve().parents[1] / "Config"
settings = {
    "DRIVE_BUNDLE_ID": args.bundle_id, "DRIVE_SERVER_HOST": host,
    "DRIVE_SERVER_SCHEME": url.scheme, "DRIVE_SERVER_PORT": str(port),
}
if args.team:
    settings["DEVELOPMENT_TEAM"] = args.team
if url.scheme == "http":
    # Xcode expands plist string values, but leaves dictionary keys literal.
    # Write the one-host transport exception into ignored local copies.
    local = config / "Local"
    local.mkdir(exist_ok=True)
    for target in ("App", "Widget"):
        name = target + ".plist"
        info = plistlib.loads((config / name).read_bytes())
        info["NSAppTransportSecurity"] = {"NSExceptionDomains": {host: {"NSExceptionAllowsInsecureHTTPLoads": True}}}
        (local / name).write_bytes(plistlib.dumps(info, sort_keys=False))
        settings["DRIVE_" + target.upper() + "_PLIST"] = "Config/Local/" + name
(config / "Local.xcconfig").write_text("".join(f"{k} = {v}\n" for k, v in settings.items()))
print("Local build settings are ready.")
