# Macrodroid Hardware Launch Profiles & Configurations

Macrodroid 5.4 provides hardware-tuned launch profiles engineered specifically for Apple Silicon (M1, M2, M3, M4 series). Profiles configure host vCPU allocation, guest RAM, graphics backend (Vulkan via ASG / ANGLE), display refresh rates, and thermal thresholds.

---

## 1. System Launch Profiles

Users can select or hot-swap profiles via `Window > Runtime Settings` (`Cmd+,`) or via the profile selector in the Control Bar HUD.

### Specification Matrix

| Profile Name | Target Resolution | Target FPS | vCPU | Guest RAM | Graphics Backend | Ideal Use Case |
|---|---|---|---|---|---|---|
| **Competitive E-Sports** | 2560 × 1440 (QHD) | 120 FPS | 8 | 8192 MiB | Vulkan / ASG + Triple Buffer | Fast-twitch games (Wild Rift, PUBG, CoD Mobile) |
| **Standard Gaming** *(Default)* | 1920 × 1080 (FHD) | 60 FPS | 6 | 6144 MiB | ANGLE / Metal Pass-Through | General gaming, Teamfight Tactics, AFK Journey |
| **Battery Saver / Eco** | 1600 × 900 (HD+) | 30–60 FPS | 4 | 4096 MiB | Native Metal GLES | Traveling / MacBook on battery power |
| **Multi-Instance Farming** | 1280 × 720 (HD) | 30 FPS | 2 | 2048 MiB | Headless / Offscreen Render | Running 2–4 simultaneous account instances |

---

## 2. Profile Details & Thermal Budgets

### 🏆 Competitive E-Sports (120 FPS Ultra)
- **Engine Tuning**: Unlocks guest SurfaceFlinger to 120Hz synchronization, aligning with Apple ProMotion displays.
- **Input Pipeline**: Ultra-low latency input polling (500Hz mouse sampling, sub-5ms touch translation).
- **GPU Delivery**: Vulkan-over-Metal driver pass-through with dedicated 3-stage command buffer ring.
- **Recommended Hardware**: Apple M2 Pro/Max, M3 Pro/Max, M4 Pro/Max hosts with active cooling.

### 🎮 Standard Gaming (60 FPS High — Default)
- **Engine Tuning**: Locks framerate to standard 60Hz vsync. Prioritizes rock-solid frame pacing over raw throughput.
- **Input Pipeline**: Normal 120Hz polling with motion-blur mitigation and smoothed virtual joystick deadzones.
- **Thermal Footprint**: Silent fan operation on MacBook Air (passive cooling) and Mac mini.
- **Recommended Hardware**: All Apple Silicon hardware (M1–M4 base chips and higher).

### 🔋 Battery Saver / Eco (30–60 FPS Dynamic)
- **Engine Tuning**: Dynamically adjusts frame rates based on window focus. Drops background instances to 15 FPS when minimized.
- **Power Optimization**: Throttles guest CPU core affinity to Efficiency cores (E-cores) where possible, reserving Performance cores (P-cores) for macOS system tasks.
- **Recommended Hardware**: Any MacBook operating on battery.

### ⚡ Multi-Instance Farming (30 FPS Per Window)
- **Engine Tuning**: Lightweight footprint designed to maximize simultaneous instances. Limits memory cache and disables high-bitrate audio streaming for background windows.
- **Port Offset**: Automatically establishes isolated loopback endpoints:
  - Instance 1: gRPC `5582`, ADB `5038`
  - Instance 2: gRPC `5584`, ADB `5040`
  - Instance 3: gRPC `5586`, ADB `5042`
- **Recommended Hardware**: Mac Studio, Mac Pro, or high-RAM Mac mini setups running botting/farming workflows.

---

## 3. Game-Specific Profile Recommendations

### Teamfight Tactics (TFT) / Auto-Battlers
- **Recommended Profile**: *Standard Gaming (60 FPS)* or *Competitive (120 FPS)*.
- **In-Game Settings**: Graphic Quality High, Framerate Cap 60 or 120, Riot Performance Mode OFF.
- **Keybindings**: MOBA / Auto-Chess preset (`D` reroll, `F` level up, `1-5` purchase champions).

### League of Legends: Wild Rift
- **Recommended Profile**: *Competitive E-Sports (120 FPS)*.
- **In-Game Settings**: 120 FPS enabled, Shadow Quality Medium, Post-Processing High.
- **Keybindings**: MOBA Skillshots preset (Smart Cast with cursor targeting `Q`, `W`, `E`, `R`, `Space` attack-move).

### Genshin Impact & Honkai: Star Rail
- **Recommended Profile**: *Standard Gaming (60 FPS High)*.
- **In-Game Settings**: 60 FPS, Render Resolution 1.0, Shadows Medium.
- **Keybindings**: Action RPG preset (`WASD` movement, Left Click attack, `Shift` dodge, `E` skill, `Q` burst).

### PUBG Mobile / Call of Duty: Mobile
- **Recommended Profile**: *Competitive E-Sports (120 FPS)*.
- **In-Game Settings**: Smooth Graphics, Extreme/90/120 FPS frame rate.
- **Keybindings**: Smart Aim FPS preset (Mouse Look with Right Click aim lock, `Alt` cursor release, `LMB` fire).

---

## 4. Configuration Storage & Persistence

Launch profiles are managed through `RuntimeSettingsWindowController` and persisted locally in:
- **UserDefaults**: Active profile ID, display resolution preferences, and audio device mappings.
- **Database**: Historical run performance indexed by profile ID in `~/Library/Application Support/Macrodroid/Captures/latest/Macrodroid_RUNTIME.sqlite`.
