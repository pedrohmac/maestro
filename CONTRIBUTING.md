# Contributing to Maestro

Thanks for your interest in contributing to Maestro!

## Building from Source

### Prerequisites

- macOS 14.0+ (Sonoma)
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Claude CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated

### Setup

```bash
git clone https://github.com/user/maestro.git
cd maestro
xcodegen generate
open Maestro.xcodeproj
```

Build and run the **Maestro** scheme in Xcode.

### Project Structure

- **Maestro/** — SwiftUI app target (views, services, app entry point)
- **MaestroCore/** — Shared library (models, store, services used by both app and CLI)
- **CLI/** — `maestro` command-line tool

## Making Changes

1. Fork the repo and create a branch from `main`
2. Make your changes
3. Run `xcodegen generate` if you added/removed files
4. Build and test: `xcodebuild -scheme Maestro -configuration Debug build`
5. Open a pull request

## Guidelines

- Follow existing code patterns and naming conventions
- SwiftUI views go in `Maestro/Views/`, organized by feature
- Models go in `MaestroCore/Models/`
- Services go in the appropriate target's `Services/` directory
- Keep PRs focused — one feature or fix per PR

## Reporting Issues

Open an issue on GitHub with:
- What you expected to happen
- What actually happened
- Steps to reproduce
- macOS version and Xcode version

## License

By contributing, you agree that your contributions will be licensed under the same [BSL 1.1](LICENSE) license that covers the project.
