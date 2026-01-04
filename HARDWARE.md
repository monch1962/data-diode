# 🏗️ Industrial Hardware Recommendations

For mission-critical OT deployments where standard consumer-grade Raspberry Pi boards may fail due to thermal stress, power fluctuations, or SD card corruption, we recommend the following industrial-grade alternatives.

## 🗝️ Key Industrial Requirements

When selecting hardware for remote, unattended operation, prioritize these features:

- **eMMC Storage**: On-board flash memory is far more resilient than microSD cards.
- **Wide Temperature Range**: Look for `-40°C to +85°C` (Industrial Grade) rather than `0°C to 50°C` (Commercial Grade).
- **Power Input Resilience**: Support for `9V - 36V DC` inputs with surge protection.
- **Fanless Design**: Eliminates moving parts that can fail in dusty or vibrating environments.

## 🏆 Top Alternatives to Raspberry Pi

| Device | Best For | Storage | Temp Range |
| :--- | :--- | :--- | :--- |
| **Revolution Pi (RevPi)** | PLC-style DIN Rail mounting | eMMC | -25°C to +55°C |
| **Raspberry Pi CM4 (Industrial)** | Custom carrier board integration | eMMC | -20°C to +85°C |
| **BeagleBone Black Industrial** | Legacy IO and extreme stability | eMMC | -40°C to +85°C |
| **Geniatech XPI-iMX8MM** | Direct Pi form-factor replacement | eMMC | -40°C to +105°C |
| **Compulab IOT-GATE-IMX8** | Hardened IoT Gateway (Enclosed) | eMMC | -40°C to +80°C |

---

## 🚀 1. Revolution Pi (RevPi)

Based on the Raspberry Pi Compute Module but housed in a professional DIN-rail enclosure.

- **Pros**: Meets EN 61131-2 (PLC standard), robust 24V power supply, industrial I/O modules.
- **Cons**: Pricier than a standard Pi.

## 🧩 2. Raspberry Pi Compute Module 4 (CM4)

The CM4 (Lite or with eMMC) can be plugged into third-party industrial carrier boards (e.g., from Seeed Studio or Waveshare).

- **Pros**: Full compatibility with our current `data_diode` software and Nerves.
- **Cons**: Requires selecting a high-quality carrier board for power/thermal stability.

## 🦴 3. BeagleBone Black Industrial

A long-standing favorite in the OT community.

- **Pros**: Superior GPIO management (PRU units), extreme temperature range, proven longevity.
- **Cons**: Slightly lower CPU performance compared to Pi 4/5.

## 🐋 4. Advantech / SECO / Toradex

These manufacturers produce "System on Modules" (SoM) designed specifically for harsh environments.

- **Pros**: 10+ year availability guarantees, medical/industrial certifications.
- **Cons**: Often requires custom development or specialized enclosures.

---

## 🌐 Network Isolation Strategies (Single Interface)

If you are deploying on a standard Raspberry Pi with only one on-board Ethernet port (`eth0`), use one of the following strategies to achieve the required network separation.

### 1. USB-to-Ethernet Adapters (Recommended)

This is the most secure and physically straightforward approach.

- **Setup**: Plug an industrial USB 3.0 Ethernet adapter into the Pi.
- **Topology**:
  - `eth0` (On-board): Connect to the **Secure Network (S2)**.
  - `eth1` (USB): Connect to the **Insecure Network (S1)**.
- **App Config**:

    ```bash
    export LISTEN_IP=10.0.1.5 # Insecure IP (eth1)
    export LISTEN_IP_S2=127.0.0.1 # Secure internal link
    ```

### 2. VLAN Tagging (802.1Q)

If you have a managed industrial switch, you can use a single cable to carry both S1 and S2 traffic in isolated virtual networks.

- **Setup**: Configure the switch port as a "Trunk" and create two sub-interfaces on the Pi.
- **Topology**:
  - `eth0.10`: VLAN 10 (Insecure).
  - `eth0.20`: VLAN 20 (Secure).
- **App Config**: Bind S1 to the IP on `eth0.10` and S2 to `eth0.20`.

### 3. Interface Binding (Software Isolation)

For development or low-risk environments, you can run multiple IP addresses on the same interface and bind the software components to prevent cross-talk.

- **Setup**: Use `ip addr add` to assign two IPs to `eth0`.
- **Note**: This provides **zero physical isolation** and is only recommended for testing the application logic.

---

**Final Recommendation**: If you need DIN rail mounting and ease of setup, go with the **Revolution Pi Connect**. If you are building a custom appliance, use the **Raspberry Pi CM4 (Industrial)** with a hardened carrier board.
