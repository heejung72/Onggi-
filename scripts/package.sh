#!/bin/bash
# 친구에게 보낼 배포용 zip 만들기 → dist/Onggi.zip
set -euo pipefail
cd "$(dirname "$0")/.."

xcodegen generate
xcodebuild -project Onggi.xcodeproj -scheme Onggi -configuration Release \
  -derivedDataPath build clean build | tail -n 5

APP="build/Build/Products/Release/Onggi.app"
mkdir -p dist
rm -f dist/Onggi.zip
ditto -c -k --keepParent "$APP" dist/Onggi.zip
echo "완료: dist/Onggi.zip  (docs/친구용_설치안내.md 와 함께 보내세요)"
