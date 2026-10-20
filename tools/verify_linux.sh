#!/bin/bash
# Executes the canonical Core tests in an official Swift Linux container. Does
# not compile UIKit, PencilKit, PDFKit or substitute for Apple UI/device tests.
set -euo pipefail
cd /workspace
source_dir="$(mktemp -d /build/neuralnotes-source-XXXXXX)"
cp Package.swift "$source_dir/Package.swift"
cp -a Tests "$source_dir/Tests"
mkdir -p "$source_dir/NeuralNotes"
cp -a NeuralNotes/Core "$source_dir/NeuralNotes/Core"
swift --version
swift test --package-path "$source_dir" --scratch-path /build/swift-cache --jobs 4
