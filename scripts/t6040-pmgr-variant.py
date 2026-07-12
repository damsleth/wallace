#!/usr/bin/env python3
"""Create reproducible T6040 PMGR topology-isolation variants.

The input is the raw ADT-generated t6040-pmgr.dtsi.  This tool deliberately
changes topology only: it never adds power-state policy properties such as
apple,preserve-active or apple,skip-auto-enable.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path


DOMAIN_START_RE = re.compile(
    r"^\tps_([a-z0-9_]+): power-controller@[0-9a-f]+ \{$"
)
CONTROLLER_RE = re.compile(r"^&pmgr([0-3]) \{$")
POWER_DOMAINS_RE = re.compile(r"^(\t\t)power-domains = ([^;]*);\n$")
PHANDLE_RE = re.compile(r"<&ps_([a-z0-9_]+)>")


@dataclass(frozen=True)
class Domain:
    label: str
    controller: int
    text: str


def is_core_infra(label: str) -> bool:
    """The narrow core-infrastructure set named in NEXT_STEPS.md."""
    return bool(
        label == "soc_dpe"
        or re.match(r"^amcc[0-9]+$", label)
        or re.match(r"^dcs_[0-9]+$", label)
        or re.match(r"^fab[0-9]+_soc$", label)
        or re.match(r"^fab_gw_", label)
        or label == "fab_afr"
    )


def is_curated_exclusion(label: str) -> bool:
    """Session-2/yuka-t8132 class exclusions, preserved exactly."""
    return bool(
        re.match(r"^(ecpu_|pcpu0_|pcpu1_)", label)
        or label in {"ecpm", "pcpm0", "pcpm1"}
        or re.match(r"^amcc[0-9]", label)
        or re.match(r"^dcs_", label)
        or re.match(r"^fab[0-9]+_soc$", label)
        or re.match(r"^fab_gw_", label)
        or label == "fab_afr"
        or label in {"pms", "afi", "afc", "rom", "sbr"}
    )


def split_source(text: str) -> list[str | Domain]:
    """Split a generated dtsi into ordinary text and domain blocks."""
    lines = text.splitlines(keepends=True)
    parts: list[str | Domain] = []
    plain: list[str] = []
    controller: int | None = None
    i = 0

    def flush_plain() -> None:
        if plain:
            parts.append("".join(plain))
            plain.clear()

    while i < len(lines):
        controller_match = CONTROLLER_RE.match(lines[i].rstrip("\n"))
        if controller_match:
            controller = int(controller_match.group(1))

        domain_match = DOMAIN_START_RE.match(lines[i].rstrip("\n"))
        if not domain_match:
            plain.append(lines[i])
            i += 1
            continue

        if controller is None:
            raise ValueError(f"domain before PMGR controller at line {i + 1}")

        flush_plain()
        block: list[str] = []
        while i < len(lines):
            block.append(lines[i])
            i += 1
            if block[-1].rstrip("\n") == "\t};":
                break
        else:
            raise ValueError(f"unterminated domain {domain_match.group(1)}")

        parts.append(
            Domain(domain_match.group(1), controller, "".join(block))
        )

    flush_plain()
    return parts


def rewrite_parents(
    domain: Domain, excluded: set[str], flatten_pmgr1: bool
) -> tuple[str, int]:
    """Drop excluded parents, or all parents for the pmgr1 flatten test."""
    rewritten: list[str] = []
    changed = 0

    for line in domain.text.splitlines(keepends=True):
        match = POWER_DOMAINS_RE.match(line)
        if not match:
            rewritten.append(line)
            continue

        parents = PHANDLE_RE.findall(match.group(2))
        kept = [] if flatten_pmgr1 and domain.controller == 1 else [
            parent for parent in parents if parent not in excluded
        ]
        if kept == parents:
            rewritten.append(line)
            continue

        changed += 1
        if kept:
            refs = ", ".join(f"<&ps_{parent}>" for parent in kept)
            rewritten.append(f"{match.group(1)}power-domains = {refs};\n")

    return "".join(rewritten), changed


def transform(text: str, mode: str) -> tuple[str, dict[str, object]]:
    parts = split_source(text)
    domains = [part for part in parts if isinstance(part, Domain)]

    if mode == "raw":
        excluded: set[str] = set()
        flatten_pmgr1 = False
    elif mode == "core-infra-pruned":
        excluded = {domain.label for domain in domains if is_core_infra(domain.label)}
        flatten_pmgr1 = False
    elif mode == "pmgr1-reparent-only":
        excluded = set()
        flatten_pmgr1 = True
    elif mode == "pmgr1-prune-only":
        excluded = {
            domain.label
            for domain in domains
            if domain.controller == 1 and is_curated_exclusion(domain.label)
        }
        flatten_pmgr1 = False
    elif mode == "curated":
        excluded = {
            domain.label for domain in domains if is_curated_exclusion(domain.label)
        }
        flatten_pmgr1 = False
    else:
        raise ValueError(f"unknown mode: {mode}")

    output: list[str] = []
    parent_lines_changed = 0
    kept_labels: set[str] = set()
    for part in parts:
        if isinstance(part, str):
            output.append(part)
            continue
        if part.label in excluded:
            continue
        kept_labels.add(part.label)
        rewritten, changed = rewrite_parents(part, excluded, flatten_pmgr1)
        output.append(rewritten)
        parent_lines_changed += changed

    result = "".join(output)
    referenced = set(PHANDLE_RE.findall(result))
    dangling = sorted(referenced - kept_labels)
    if dangling:
        raise ValueError("dangling PMGR labels: " + ", ".join(dangling))

    summary: dict[str, object] = {
        "mode": mode,
        "input_domains": len(domains),
        "output_domains": len(kept_labels),
        "removed_domains": len(excluded),
        "parent_lines_changed": parent_lines_changed,
        "removed_labels": sorted(excluded),
    }
    return result, summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode",
        choices=(
            "raw",
            "core-infra-pruned",
            "pmgr1-reparent-only",
            "pmgr1-prune-only",
            "curated",
        ),
    )
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()

    result, summary = transform(args.source.read_text(), args.mode)
    args.destination.write_text(result)
    print(
        f"{summary['mode']}: {summary['input_domains']} -> "
        f"{summary['output_domains']} domains; removed "
        f"{summary['removed_domains']}; changed "
        f"{summary['parent_lines_changed']} parent lines",
        file=sys.stderr,
    )
    if summary["removed_labels"]:
        print(
            "removed: " + " ".join(summary["removed_labels"]),
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
