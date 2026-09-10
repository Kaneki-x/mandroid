#!/bin/zsh
# Regenerates MadroidKit/Generated from Protos/*.proto.
#
# Builds protoc-gen-swift and protoc-gen-grpc-swift-2 from the pinned
# Tools/protoc-plugins package (SwiftPM), then runs Homebrew protoc.
# Output is committed; run this after touching Protos/ and commit the result.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGINS="$ROOT/Tools/protoc-plugins"
OUT="$ROOT/MadroidKit/Generated"
PROTOC="${PROTOC:-$(command -v protoc || true)}"

if [[ -z "$PROTOC" ]]; then
  echo "protoc not found; brew install protobuf" >&2
  exit 1
fi

echo "==> building protoc plugins (release)"
( cd "$PLUGINS" && swift build -c release \
    --product protoc-gen-swift \
    --product protoc-gen-grpc-swift-2 >/dev/null )
BIN="$(cd "$PLUGINS" && swift build -c release --show-bin-path)"

mkdir -p "$OUT"
setopt null_glob; rm -f "$OUT"/*.pb.swift "$OUT"/*.grpc.swift; unsetopt null_glob

echo "==> protoc ($("$PROTOC" --version))"
"$PROTOC" \
  --proto_path="$ROOT/Protos" \
  --plugin=protoc-gen-swift="$BIN/protoc-gen-swift" \
  --plugin=protoc-gen-grpc-swift-2="$BIN/protoc-gen-grpc-swift-2" \
  --swift_opt=Visibility=Public \
  --swift_opt=FileNaming=DropPath \
  --swift_out="$OUT" \
  --grpc-swift-2_opt=Visibility=Public \
  --grpc-swift-2_opt=Client=true \
  --grpc-swift-2_opt=Server=false \
  --grpc-swift-2_opt=FileNaming=DropPath \
  --grpc-swift-2_out="$OUT" \
  "$ROOT"/Protos/*.proto

echo "==> wrote:"
ls -1 "$OUT"
