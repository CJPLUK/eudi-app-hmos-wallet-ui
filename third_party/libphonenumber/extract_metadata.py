#!/usr/bin/env python3
"""Extract the validation-relevant subset of libphonenumber metadata.

Source of truth is PhoneNumberKit's bundled PhoneNumberMetadata.json (which is a
JSON rendering of Google's libphonenumber PhoneNumberMetadata.xml). The iOS app
validates phone numbers through PhoneNumberKit, so the Cangjie port must use the
same table to stay behaviour-compatible.

Usage:
    python3 extract_metadata.py <path-to-PhoneNumberMetadata.json> [-o phone_metadata.json]

The default input lives inside the Xcode SPM checkout, which is ephemeral — that
is exactly why the extracted subset is vendored next to this script.
"""
import argparse, json, re, sys, collections

# Number types libphonenumber can assign. A number is "valid" when it matches
# the general description AND at least one of these (PhoneNumberKit rejects
# type == .unknown when parsing with ignoreType: false).
TYPES = ["fixedLine", "mobile", "tollFree", "premiumRate", "sharedCost",
         "personalNumber", "voip", "pager", "uan", "voicemail"]


def pattern(node, key):
    v = node.get(key)
    if isinstance(v, dict):
        p = v.get("nationalNumberPattern")
        if isinstance(p, str):
            return " ".join(p.split())
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("-o", "--out", default="phone_metadata.json")
    args = ap.parse_args()

    raw = json.load(open(args.source, encoding="utf-8"))
    territories = raw["phoneNumberMetadata"]["territories"]["territory"]

    out, stats = [], collections.Counter()
    for t in territories:
        general = pattern(t, "generalDesc")
        if not general:
            stats["skipped_no_general"] += 1
            continue
        types = {k: p for k in TYPES if (p := pattern(t, k))}
        if not types:
            # Without any type pattern every number would be type .unknown,
            # i.e. nothing could ever validate. Skip so the Cangjie side can
            # fall back instead of silently rejecting everything.
            stats["skipped_no_types"] += 1
            continue
        np_parsing = t.get("nationalPrefixForParsing") or t.get("nationalPrefix") or ""
        transform = t.get("nationalPrefixTransformRule") or ""
        if transform:
            stats["has_transform_rule"] += 1
        if np_parsing:
            stats["has_national_prefix"] += 1
        # libphonenumber ships a canonical example per type. Every one of them
        # must validate, which makes them a cheap regression net over the whole
        # table (see testValidatePhoneNumberExampleNumbers).
        examples = []
        for k in TYPES:
            v = t.get(k)
            if isinstance(v, dict):
                ex = v.get("exampleNumber")
                if isinstance(ex, str) and ex.strip():
                    examples.append(ex.strip())

        out.append({
            "id": t["id"],
            "countryCode": str(t["countryCode"]),
            "nationalPrefixForParsing": " ".join(np_parsing.split()),
            "nationalPrefixTransformRule": transform,
            "general": general,
            "types": [types.get(k, "") for k in TYPES],
            "examples": sorted(set(examples)),
        })

    out.sort(key=lambda r: r["id"])
    json.dump({
        "_provenance": {
            "source": "PhoneNumberKit PhoneNumberMetadata.json (libphonenumber)",
            "phonenumberkit_version": "5.0.4",
            "phonenumberkit_revision": "ab06a8333394f4a4fb6eecca447dae0aa06c1eca",
            "types_order": TYPES,
        },
        "regions": out,
    }, open(args.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)

    print(f"wrote {args.out}: {len(out)} regions")
    for k, v in sorted(stats.items()):
        print(f"  {k}: {v}")
    chars = sum(len(r["general"]) + sum(len(x) for x in r["types"]) for r in out)
    print(f"  total pattern chars: {chars:,}")


if __name__ == "__main__":
    sys.exit(main())
