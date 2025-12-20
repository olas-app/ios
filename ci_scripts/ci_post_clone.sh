#!/bin/sh

#  ci_post_clone.sh
#  OlasApp
#
#  This script runs on Xcode Cloud after the repository is cloned.
#  It sets up the build environment by resolving Swift Package Manager dependencies.

set -e  # Exit on error

echo "==================================="
echo "Xcode Cloud Post-Clone Script"
echo "==================================="

# Navigate to project root (script runs from ci_scripts directory)
cd ..

echo "Current directory: $(pwd)"
echo "Xcode version: $(xcodebuild -version)"

# Resolve Swift Package Manager dependencies
echo ""
echo "Resolving Swift Package Manager dependencies..."
xcodebuild -resolvePackageDependencies \
    -workspace OlasApp.xcworkspace \
    -scheme OlasApp \
    -clonedSourcePackagesDirPath SourcePackages

echo ""
echo "==================================="
echo "Xcode Cloud setup complete!"
echo "==================================="
