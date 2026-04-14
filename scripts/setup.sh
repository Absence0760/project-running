#!/usr/bin/env bash
# Setup script — generates Flutter platform directories and bootstraps the monorepo.
# Run this once after cloning the repo.
#
# Prerequisites:
#   - Flutter 3.19+  (flutter.dev/docs/get-started/install)
#   - Melos           (dart pub global activate melos)
#   - Xcode 15+       (for iOS/watchOS targets)
#   - Android Studio  (for Android/Wear OS targets)
#   - Docker Desktop  (for Supabase backend)
#   - pnpm 9.x        (npm install -g pnpm)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "=== Run App — Local Setup ==="
echo ""

# --- Flutter platform directories ---
echo "▸ Generating Flutter platform directories..."

for app in mobile_ios mobile_android watch_wear; do
  APP_DIR="$ROOT/apps/$app"
  echo "  → $app"
  cd "$APP_DIR"

  case "$app" in
    mobile_ios)
      # Generate iOS platform dir
      if [ ! -d "ios" ]; then
        flutter create --platforms ios --org com.runapp --project-name run_app .
        echo "    ✓ ios/ created"
      else
        echo "    ✓ ios/ already exists"
      fi
      ;;
    mobile_android)
      # Generate Android platform dir
      if [ ! -d "android" ]; then
        flutter create --platforms android --org com.runapp --project-name run_app .
        echo "    ✓ android/ created"
      else
        echo "    ✓ android/ already exists"
      fi
      ;;
    watch_wear)
      # Generate Android platform dir for Wear OS
      if [ ! -d "android" ]; then
        flutter create --platforms android --org com.runapp --project-name run_wear .
        echo "    ✓ android/ created (Wear OS)"
      else
        echo "    ✓ android/ already exists"
      fi
      ;;
  esac
done

cd "$ROOT"

# --- Melos bootstrap ---
echo ""
echo "▸ Running melos bootstrap..."
if command -v melos &>/dev/null; then
  melos bootstrap
  echo "  ✓ Dart packages bootstrapped"
else
  echo "  ⚠ Melos not found. Install with: dart pub global activate melos"
  echo "    Then run: melos bootstrap"
fi

# --- Web app ---
echo ""
echo "▸ Installing web app dependencies..."
cd "$ROOT/apps/web"
if command -v pnpm &>/dev/null; then
  pnpm install
  echo "  ✓ Web dependencies installed"
else
  echo "  ⚠ pnpm not found. Install with: npm install -g pnpm"
fi

# --- Web env file ---
if [ ! -f ".env.local" ] && [ -f ".env.example" ]; then
  cp .env.example .env.local
  echo "  ✓ .env.local created from .env.example (edit with your keys)"
fi

# --- Backend env file ---
cd "$ROOT/apps/backend"
if [ ! -f ".env.local" ] && [ -f ".env.example" ]; then
  cp .env.example .env.local
  echo "  ✓ Backend .env.local created"
fi

cd "$ROOT"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "To run each app:"
echo ""
echo "  Web:           cd apps/web && pnpm dev"
echo "  iOS:           cd apps/mobile_ios && flutter run -d iPhone"
echo "  Android:       cd apps/mobile_android && flutter run -d emulator-5554"
echo "  Wear OS:       cd apps/watch_wear && flutter run -d <wear-device>"
echo "  Apple Watch:   open apps/watch_ios/WatchApp.xcodeproj → Cmd+R"
echo "  Backend:       cd apps/backend && supabase start"
echo ""
echo "See docs/local_testing_*.md for detailed instructions."
