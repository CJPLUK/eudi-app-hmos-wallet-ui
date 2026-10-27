#!/usr/bin/env python3
"""Generate the Cangjie phone-number metadata table from the vendored subset.

    python3 gen_phone_metadata.py            # writes the .cj next to the validator
    python3 gen_phone_metadata.py --check    # verify the checked-in .cj is current

Each region becomes one tab-separated record with a fixed 15 fields:
    id, countryCode, nationalPrefixForParsing, nationalPrefixTransformRule,
    generalPattern, then 10 type patterns in TYPES order (empty = absent).
Fixed arity means the parser needs no list separator, and patterns themselves
never contain a tab or newline (whitespace was collapsed during extraction).
"""
import argparse, json, pathlib, sys

HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_OUT = (HERE.parent.parent / "Modules/eudi_logic_business/src/main/cangjie"
               / "phone_metadata.cj")


def cj_string(s: str) -> str:
    """Escape a Python string into a Cangjie double-quoted literal body.

    `$` is deliberately left alone: Cangjie interpolation is strictly `${expr}`,
    so a bare `$` (as in the `$1` of a nationalPrefixTransformRule, or the `$`
    anchor inside a prefix regex) is literal. Escaping it as `\\$` would instead
    rely on that being a recognised escape, which it is not. The caller asserts
    no field contains `${`.
    """
    return s.replace("\\", "\\\\").replace('"', '\\"')


def build(data) -> str:
    prov = data["_provenance"]
    regions = data["regions"]
    lines = [
        "/*",
        " * GENERATED FILE — do not edit by hand.",
        " *",
        " * Regenerate with:",
        " *   python3 third_party/libphonenumber/gen_phone_metadata.py",
        " *",
        f" * Source: {prov['source']}",
        f" * PhoneNumberKit {prov['phonenumberkit_version']} ({prov['phonenumberkit_revision'][:12]})",
        " *",
        " * The iOS app validates phone numbers via PhoneNumberKit, so the Cangjie",
        " * port has to use the same libphonenumber table to stay behaviour-compatible.",
        " * One tab-separated record per region, 15 fixed fields:",
        " *   id, countryCode, nationalPrefixForParsing, nationalPrefixTransformRule,",
        " *   generalPattern, " + ", ".join(prov["types_order"]),
        " */",
        "package eudi_logic_business",
        "",
        f"/** {len(regions)} regions, libphonenumber order-independent (sorted by region id). */",
        "let PHONE_METADATA_RECORDS: Array<String> = [",
    ]
    for r in regions:
        fields = [r["id"], r["countryCode"], r["nationalPrefixForParsing"],
                  r["nationalPrefixTransformRule"], r["general"]] + r["types"]
        assert len(fields) == 15, (r["id"], len(fields))
        for f in fields:
            assert "\t" not in f and "\n" not in f, r["id"]
            # Would be read as Cangjie string interpolation; none exists today.
            assert "${" not in f, (r["id"], f)
        lines.append('    "' + cj_string("\t".join(fields)) + '",')
    lines.append("]")
    lines.append("")
    return "\n".join(lines)


def build_examples(data) -> str:
    """Test-only companion. Kept in a `_test.cj` file so cjpm build drops it —
    the app has no reason to ship ~1100 example numbers."""
    prov = data["_provenance"]
    examples = [(r["id"], ex) for r in data["regions"] for ex in r["examples"]]
    lines = [
        "/*",
        " * GENERATED FILE — do not edit by hand.",
        " *   python3 third_party/libphonenumber/gen_phone_metadata.py",
        " *",
        f" * Source: {prov['source']}",
        f" * PhoneNumberKit {prov['phonenumberkit_version']} ({prov['phonenumberkit_revision'][:12]})",
        " *",
        " * libphonenumber's canonical example number per region and number type.",
        " * Each must validate for its own region, which makes this the regression",
        " * net over the whole metadata table (testValidatePhoneNumberExampleNumbers).",
        " * Test-only: the `_test.cj` suffix keeps it out of cjpm build output.",
        " */",
        "package eudi_logic_business",
        "",
        f"/** {len(examples)} entries, each \"region<TAB>number\". */",
        "let PHONE_EXAMPLE_NUMBERS: Array<String> = [",
    ]
    for rid, ex in examples:
        assert "\t" not in ex and "${" not in ex, (rid, ex)
        lines.append('    "' + cj_string(f"{rid}\t{ex}") + '",')
    lines.append("]")
    lines.append("")
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--source", default=str(HERE / "phone_metadata.json"))
    ap.add_argument("--out", default=str(DEFAULT_OUT))
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()

    data = json.load(open(args.source, encoding="utf-8"))
    out = pathlib.Path(args.out)
    targets = [
        (out, build(data)),
        (out.with_name("phone_metadata_examples_test.cj"), build_examples(data)),
    ]

    if args.check:
        stale = [p for p, text in targets
                 if (p.read_text(encoding="utf-8") if p.exists() else "") != text]
        if stale:
            for p in stale:
                print(f"STALE: {p} differs from generator output", file=sys.stderr)
            return 1
        print("up to date: " + ", ".join(p.name for p, _ in targets))
        return 0

    for p, text in targets:
        p.write_text(text, encoding="utf-8")
        print(f"wrote {p} ({len(text):,} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
