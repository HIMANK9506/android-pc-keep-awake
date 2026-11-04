# Android PC Keep-Awake ⚡📱

A lightweight, non-intrusive Windows daemon that keeps your Android phone awake **only when connected to your specific laptop or PC**.

When unplugged, or when plugged into a normal wall charger, power bank, or another computer, your phone sleeps normally according to its standard timeout.

---

## 💡 The Problem

Android has a built-in Developer setting called *"Stay awake while charging"*. The major issue is that once turned on, it keeps the screen awake on **every single charger** you ever plug into:
- Wall adapters
- Fast/Turbo chargers
- Power banks
- Other people's computers

If you only want your phone awake when plugged into **your own desk/laptop** (to keep an eye on notifications, development, or live dashboards), the native setting doesn't discriminate.

---

## 🚀 The Solution

`android-pc-keep-awake` runs as a silent, featherweight background daemon on **your PC**:

1. **PC-Exclusive:** It looks specifically for your authorized Android device over USB.
2. **Instant Reconnect Wake:** The second you plug your phone in, it immediately wakes the display.
3. **Lockscreen Aware:** Overcomes the standard 5-to-8 second Android lock screen timeout by gently pulsing user-activity keep-alive signals.
4. **Zero Lingering Side Effects:** Leaves the phone's global `stay_on_while_plugged_in` setting at `0` (factory default). As soon as you unplug, your phone automatically sleeps after your normal screen timeout (30s / 1m / 2m).
5. **No 3rd-Party Phone Apps Needed:** Pure ADB-based automation. No apps running on your phone, no battery drain, no root required.
6. **Featherweight:** Consumes **0.0% CPU** and less than **5 MB of RAM** on Windows.

---

## 📋 Requirements

* **Windows 10 or 11**
* **Android phone** with **USB Debugging** enabled
* **USB cable** connecting phone to your PC

---

## ⚡ Quick Start

### 1. Enable USB Debugging on your Phone
1. Go to **Settings > About phone** and tap **Build number** 7 times.
2. Go to **Settings > System > Developer options** and turn **USB debugging** to **ON**.
3. Plug your phone into your PC, unlock the phone, check *"Always allow from this computer"*, and tap **Allow**.

### 2. Install & Run
Clone this repository and run the PowerShell installer:

```powershell
git clone https://github.com/HIMANK9506/android-pc-keep-awake.git
cd android-pc-keep-awake
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

The installer will:
* Detect or install ADB via `winget` (if not already present).
* Register the daemon in your Windows Startup folder (`Shell:startup`).
* Start the background daemon immediately without showing any console window.

---

## 🛠️ Management & Commands

| Action | How-To |
| :--- | :--- |
| **Stop Watcher** | Run `stop-watcher.bat` or run `.\uninstall.ps1` |
| **Uninstall completely** | Run `powershell -ExecutionPolicy Bypass -File .\uninstall.ps1` |
| **Check running status** | `Get-Process -Name powershell \| Where-Object { $_.CommandLine -like "*phone-watcher.ps1*" }` |

---

## 🔒 Security & Privacy

* Uses official Google Android Debug Bridge (`adb.exe`).
* Operates strictly through your PC's authorized RSA key fingerprint.
* Other computers without authorization cannot interact with your device.
* Does not modify system firmware, bootloader, or root state.

---

## 📄 License

This project is licensed under the [MIT License](LICENSE) - see the LICENSE file for details.
