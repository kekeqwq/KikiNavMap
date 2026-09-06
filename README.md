# KikiNavMap ✈️

<p align="center">
  <img src="Sources/KikiNavMap/Resources/AppIcon.png" alt="KikiNavMap Icon" width="128" height="128" style="border-radius: 28px;" />
</p>

<p align="center">
  <b>A Minimalist, High-Performance Flight Plan Creation & Routing Tool for macOS</b>
  <br />
  <i>Crafted in Pure Swift with macOS 27 Native Liquid Glass UI & Nix Flake Environment</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2027.0+-000000?logo=apple&logoColor=white" alt="macOS 27" />
  <img src="https://img.shields.io/badge/Language-Swift%206-FA7343?logo=swift&logoColor=white" alt="Swift 6" />
  <img src="https://img.shields.io/badge/Build-Nix%20Flake-5277C3?logo=nixos&logoColor=white" alt="Nix Flake" />
  <img src="https://img.shields.io/badge/License-GPL--3.0-blue.svg" alt="License: GPL-3.0" />
</p>

---

## ✨ Features

- **Liquid Glass Floating UI (macOS 27 Native)**:
  - Translucent materials (`.ultraThinMaterial`), floating search pills, and responsive system light/dark mode adaptation.
  - Full-screen native vector Apple Maps integration (`MKMapView`) with high-contrast national borders and clean geopolitical labeling.

- **Intelligent Hand-Drawn Trajectory Snapping**:
  - **Douglas-Peucker Trajectory Fitting**: Preserves intentional user curves and straight corridors without generating artificial zigzag waypoints.
  - **Strict 5-Letter Alphabetic Waypoints**: Automatically filters out navaids, numeric fixes, and clutter, strictly snapping to standardized 5-letter fixes (`A-Z`).
  - **Right-Click Waypoint Deletion & Coordinates**: Easily delete waypoints or insert custom coordinate fixes (e.g. `60N120W`) with contextual right-click actions.

- **Great-Circle (Geodesic) Routing & Geometric Progression**:
  - Real-time geodesic curvature interpolation with rainbow gradient route visualization.
  - Minimum-detour insertion ordering: guarantees the flight plan sequence follows the geometric flight path progression from Departure to Destination, regardless of clicking order.

- **Global Multi-Field Airport Search**:
  - Built-in database of 19,280+ worldwide airports.
  - Instant search by **ICAO** (`OTHH`, `EFHK`), **IATA** (`DOH`, `HEL`, `JFK`, `DXB`), **City** (`Doha`, `Helsinki`), or **Airport Name**.
  - Non-intrusive floating suggestion list with instantaneous dismissal upon selection.

- **Offline MSFS 2024 / Navigraph BGL NavData Engine**:
  - Pure Swift high-performance binary BGL parser for modern flight simulator navigation datasets (such as AIRAC 2606).
  - Spatial KD-Tree spatial indexing for sub-millisecond nearest-waypoint queries.
  - Automatic AIRAC cycle detection (e.g. `AIRAC 2606 Active`) and one-click cycle folder import.

- **Hermetic Reproducible Builds**:
  - Managed with **Nix Flakes** (`flake.nix`) for reproducible compilation across macOS environments.

---

## 🎮 Interaction & Controls

| Action | Control | Description |
| :--- | :--- | :--- |
| **Pan Map** | Left-Click + Drag | Smoothly pan across countries and continents |
| **Zoom Map** | Mouse Scroll Wheel | Zoom in and out |
| **Draw Flight Route** | `Shift` + Left-Click Drag | Freehand drawing; snaps cleanly to 5-letter fixes along the stroke |
| **Snap Single Fix** | `Shift` + Left-Click | Point-and-click to snap the nearest 5-letter fix or coordinate |
| **Delete Waypoint** | Right-Click on Waypoint | Removes the targeted waypoint from the active route |
| **Insert Coordinate** | Right-Click on Empty Map | Inserts an oceanic/remote coordinate fix (e.g. `60N120W`) |
| **Search Airport** | Type in `DEP` / `DEST` | Search by ICAO, IATA, or City; press `Return` or click to select |
| **Copy Route** | Click `Copy Route` | Copies standard ICAO flight plan string to clipboard |

---

## 🚀 Building & Running

### Using Nix Flake (Recommended)

```bash
# Run directly
nix run github:kekeqwq/KikiNavMap

# Or build the .app bundle locally
nix build
open result/Applications/KikiNavMap.app
```

### Building with Swift CLI

```bash
# Run unit test suite
swift test

# Build executable
swift build -c release
```

---

## 📂 Project Structure

```
KikiNavMap/
├── flake.nix                                # Nix Flake configuration
├── Package.swift                            # Swift Package Manager manifest
├── Info.plist                               # macOS App Bundle metadata
├── LICENSE                                  # GNU General Public License v3.0
├── README.md                                # Documentation
├── Sources/KikiNavMap/
│   ├── App/                                 # App entry point and central AppState
│   ├── Engine/                              # Geodesic calculation, RDP snapping, CoordinateFix
│   ├── Models/                              # Airport, Waypoint, RoutePoint models
│   ├── NavData/                             # BGL binary parser, KD-Tree, Airport metadata
│   ├── Views/                               # SwiftUI Views & MapKit representation
│   │   ├── About/                           # About sheet & copyright info
│   │   ├── Map/                             # InteractiveMapView subclass & overlay renderers
│   │   ├── Overlay/                         # LiquidGlassToolbar, AirportSearchField
│   │   └── Settings/                        # AIRAC cycle import & configuration
│   └── Resources/                           # AppIcon.icns, world borders, 19k airport database
└── Tests/KikiNavMapTests/                   # Verification suite (RDP, KDTree, Geodesic, Search)
```

---

## 📜 License

Copyright © 2026 [kekeqwq](https://github.com/kekeqwq).

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)**. See the [LICENSE](LICENSE) file for details.

