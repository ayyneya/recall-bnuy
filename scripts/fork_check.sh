#!/bin/bash
# Everything discord-full must pass before a release. Run from the repository root.
set -euo pipefail
scratch=$(mktemp -d);trap 'rm -rf "$scratch"' EXIT
flags=(-O -target arm64-apple-macos26.5 -parse-as-library)
sources=$(find app/Sources -name '*.swift' ! -name Main.swift | sort)
swiftc "${flags[@]}" $sources app/Sources/Main.swift -o "$scratch/app"
for test in SupportReportTests HelpSearchTests LogBundleTests UpdateOfferTests MacOSShadersTests;do
    mkdir -p "$scratch/$test"
    # The support report test runs as a process named ow2-setup.
    binary=$scratch/$test/$([ $test = SupportReportTests ] && echo ow2-setup || echo run)
    swiftc "${flags[@]}" $sources "tests/$test.swift" -o "$binary"
    "$binary"
done
swiftc "${flags[@]}" app/Sources/Localization.swift app/Sources/Brand.swift app/Sources/SetupService.swift app/Sources/UpdateService.swift tests/UpdateServiceTests.swift -o "$scratch/update"
"$scratch/update"
python3 tests/test_discord.py
python3 tests/test_localization.py
python3 tests/run_advanced_settings.py
