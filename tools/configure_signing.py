"""Create local signing configuration without modifying an existing setup."""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--team", required=True, help="10-character Apple developer Team ID")
parser.add_argument("--bundle", required=True, help="Your registered app bundle identifier")
mode = parser.add_mutually_exclusive_group(required=True)
mode.add_argument("--cloud-container", help="Your registered iCloud container identifier")
mode.add_argument("--local-only", action="store_true", help="Sign without iCloud capabilities")
args = parser.parse_args()
identifier = r"[A-Za-z][A-Za-z0-9-]*(?:\.[A-Za-z][A-Za-z0-9-]*)+"
if not re.fullmatch(r"[A-Z0-9]{10}", args.team):
    parser.error("Team ID must be 10 uppercase letters or digits.")
if not re.fullmatch(identifier, args.bundle) or args.bundle.startswith("org.example."):
    parser.error("Provide your own reverse-domain app bundle identifier.")
if args.cloud_container and not re.fullmatch(r"iCloud\." + identifier, args.cloud_container):
    parser.error("Provide a container identifier beginning with iCloud.")
destination = ROOT / "Config/Signing.local.xcconfig"
lines = [f"DEVELOPMENT_TEAM = {args.team}", f"BABYBUDDY_BUNDLE_IDENTIFIER = {args.bundle}"]
if args.cloud_container:
    lines += [f"BABYBUDDY_CLOUD_CONTAINER = {args.cloud_container}",
              "BABYBUDDY_ENTITLEMENTS = iOS/BabyBuddy.entitlements",
              "BABYBUDDY_MAC_ENTITLEMENTS = iOS/BabyBuddyMac.entitlements"]
try:
    with destination.open("x", encoding="utf-8") as output:
        output.write("\n".join(lines) + "\n")
except FileExistsError:
    parser.error(f"{destination} already exists. Edit it directly to preserve your setup.")
print(f"Created {destination}")
print("Open Xcode, select this team and register the app ID and iCloud capabilities before building for a device.")
