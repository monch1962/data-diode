# 📦 Raspberry Pi Packaging Options

For deploying the `data_diode` application to a Raspberry Pi in an OT environment, several packaging strategies are available. The best choice depends on your infrastructure and security requirements.

| Option | Best For | Pros | Cons |
| :--- | :--- | :--- | :--- |
| **Mix Release** | Simple standalone deploy | Standard Elixir, self-contained, easy `systemd` integration. | Requires pre-installed OS (Raspberry Pi OS). |
| **Docker** | Containerized fleets | Portability, isolation, easy rollback. | Additional overhead of Docker engine on the Pi. |
| **Nerves Project** | Mission-Critical / Hardened | Boots into the app, read-only firmware, ultra-fast boot, minimal attack surface. | Steeper learning curve, requires firmware-level management. |
| **Debian (.deb)** | Standard IT Repo management | Familiar for Linux admins, managed via `apt`, handles dependencies. | requires `repmgr` or similar for build automation. |

---

## 🔝 1. The "Gold Standard": Nerves Project
If you are building a dedicated hardware appliance, **Nerves** is highly recommended.
- **Boot Time**: < 5 seconds.
- **Security**: The entire OS is a ~30MB read-only firmware image. No shell (by default), no SSH (optional), no generic Linux vulnerabilities.
- **Self-Healing**: Built-in A/B firmware partitions and watchdog support.
- **How to start**: `mix nerves.new` (requires a separate sub-project for the firmware build).

### ✅ Compatibility Verification
To ensure the app "just works" on Nerves, run the compatibility audit:
```bash
mix test test/nerves_compatibility_test.exs
```
This verifies that:
- No hardcoded absolute OS paths are used (except hardware `/sys`).
- Logic is environment-configured via `runtime.exs`.
- Shell utility calls (`df`) are BusyBox-safe.

## 🐋 2. Docker / BalenaCloud
For managing large fleets of Pi devices remotely.
- **BalenaCloud**: A managed service specifically for Raspberry Pi fleets. They use a special container engine (balenaEngine) optimized for SD cards.
- **Ease of Use**: Push your code, and it deploys across hundreds of devices with a rich dashboard.

## 📦 3. OS-Native (.deb)
If your organization uses standard Linux package management.
- Use `mix_deb` or `bakeware` to wrap your release into a `.deb` file.
- Field technicians can install it with `sudo apt install ./data_diode.deb`.
- Automatically handles `systemd` unit file installation.

## 🛠️ 4. Standalone Release (Current Implementation)
Our current **[`README.md`](file:///Users/davidm/Projects/elixir-spike/data_diode/README.md)** uses `mix release`. This is the most flexible for manual on-site deployment where the Pi already has a standard OS installed.

---
**Recommendation**: Start with **Mix Release** for early field trials. Move to **Nerves** for the final production industrial appliance.
