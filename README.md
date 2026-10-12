# Keycloak for Windows

[![Build](https://github.com/taizod1024/keycloak/actions/workflows/check-and-build-daily.yml/badge.svg)](https://github.com/taizod1024/keycloak/actions/workflows/check-and-build-daily.yml)
[![Release](https://img.shields.io/github/v/release/taizod1024/keycloak)](https://github.com/taizod1024/keycloak/releases)

Keycloak packaging for Windows via winget.

## Overview

This repository provides automated builds and packaging of [Keycloak](https://www.keycloak.org/), an open-source identity and access management (IAM) server.

- **Source**: Built from the [official Keycloak source](https://github.com/keycloak/keycloak)
- **Packaging**: Packaged for [winget](https://github.com/microsoft/winget-pkgs) with Windows launcher
- **Automation**: Daily version checks and automated builds on upstream updates
- **License**: Apache-2.0 (Keycloak upstream)

## Installation

### Via winget

```cmd
winget install taizod1024.keycloak
```

### Manual Installation

Download the latest release from [GitHub Releases](https://github.com/taizod1024/keycloak/releases) and extract the zip file.

## Usage

After installation, run Keycloak from the command line:

```cmd
kc.exe start-dev
```

Or use the batch script directly:

```cmd
keycloak\bin\kc.bat start-dev
```

For more options and configuration, refer to [Keycloak Documentation](https://www.keycloak.org/documentation).

## Technical Details

- **Build Source**: Official Keycloak releases from [keycloak/keycloak](https://github.com/keycloak/keycloak)
- **Runtime**: Windows executable with launcher
- **Dependencies**: Microsoft.OpenJDK.21
- **Launcher**: `kc.exe` wrapper for `bin/kc.bat`

## Automation

This repository includes automated workflows:

- **Daily Check & Build** (`check-and-build-daily.yml`): Runs at 21:00 UTC daily
  - Checks for new upstream Keycloak releases
  - Builds and packages on version updates
  - Creates GitHub releases with artifacts
- **Publish on Release** (`publish-on-release.yml`): Triggered on release creation
  - Automatically submits new builds to winget-pkgs repository
  - Updates the `taizod1024.keycloak` package

## Licensing and Redistribution Notices

Release artifacts include license and redistribution notice files:

- Keycloak license is included under the package
- Dependencies (OpenJDK.21) follow their respective licenses

For detailed license information, refer to the [official Keycloak license](https://github.com/keycloak/keycloak/blob/main/LICENSE.txt).

## Acknowledgements

Thanks to the following projects and communities:

- [Keycloak](https://www.keycloak.org/) for the open-source IAM server
- [keycloak/keycloak](https://github.com/keycloak/keycloak) for the upstream source code
- [microsoft/winget-pkgs](https://github.com/microsoft/winget-pkgs) for the Windows package manager
- [Microsoft.OpenJDK](https://github.com/microsoft/openjdk) for the Java runtime

## Disclaimer

This project is not affiliated with, endorsed by, or sponsored by Keycloak or the Keycloak Project.

This repository provides automated packaging for Windows users. For production deployments, please refer to [official Keycloak documentation](https://www.keycloak.org/documentation) and deployment best practices.

This project is intended for development and evaluation purposes. The maintainer is not responsible for any issues or damages caused by its use.
