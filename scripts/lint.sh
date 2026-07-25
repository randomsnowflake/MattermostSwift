#!/bin/sh
set -eu

cd "$(git rev-parse --show-toplevel)"

swift format lint --strict --recursive --configuration .swift-format Sourcecode Tests
