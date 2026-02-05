# 🛣️ Botz Routing System

A **Forza Horizon-style** world-space navigation system for FiveM using DUI (Direct User Interface). This resource renders glowing tire track lanes on the road that guide players to their waypoint destination.

![FiveM Navigation](https://img.shields.io/badge/FiveM-Navigation-green)
![Lua](https://img.shields.io/badge/Language-Lua-blue)
![ox_lib](https://img.shields.io/badge/Requires-ox__lib-orange)

## 📺 Preview

[![Video Preview](https://img.youtube.com/vi/VCta3p7pWqQ/0.jpg)](https://youtu.be/VCta3p7pWqQ)

**Watch the demo:** [https://youtu.be/VCta3p7pWqQ](https://youtu.be/VCta3p7pWqQ)

---

## ⚠️ IMPORTANT NOTICE

> **This project is no longer maintained.**
> 
> Due to high resource usage (DUI rendering every frame), this resource is provided **AS-IS** with no further updates or support planned.
> 
> **Feel free to use this as a stepping stone** to build your own optimized navigation system!

---

## ✨ Features

- 🎮 **Forza Horizon-inspired** lane guidance system
- 🛤️ **Dual tire track** visual effect with glow
- 🎨 **Dynamic color coding:**
  - 🟢 **Green** - Clear road ahead
  - 🟡 **Yellow** - Turn approaching (< 30m)
  - 🔴 **Red** - Turn imminent (< 10m)
- 📍 **GPS integration** - Uses native `GenerateDirectionsToCoord`
- 🔄 **Camera-relative rendering** - Lanes stay fixed on road
- ↩️ **Wrong way detection** - Shows arrows behind when going wrong direction

---

## 📋 Requirements

- [ox_lib](https://github.com/overextended/ox_lib) - Required for DUI management

---

## 📥 Installation

1. Download or clone this repository
2. Place `botz_routingsystem` in your resources folder
3. Ensure `ox_lib` is installed and started before this resource
4. Add to your `server.cfg`:

```cfg
ensure ox_lib
ensure botz_routingsystem
```

---

## ⚙️ Configuration

Edit `client.lua` to customize:

```lua
local Config = {
    MaxArrows = 15,          -- Number of lane segments
    MinDistance = 3.0,       -- Start distance from player (meters)
    MaxDistance = 50.0,      -- Max render distance (meters)
    ArrowSpacing = 3.0,      -- Gap between segments (meters)
    ArrowSize = 0.10,        -- Lane width
    ArrowHeight = 0.22,      -- Lane length
    GroundOffset = 0.05,     -- Height above road
    -- ... more options available
}
```

---

## 🎨 Customization

### Changing Lane Appearance

Edit `dui/arrow.html` to modify:
- Track width and gap
- Glow effects
- Gradient fade

### Changing Colors

In `client.lua`, find the color section in `DrawArrows()`:

```lua
local r, g, b = 0, 255, 100  -- Default green
-- Modify these values for different colors
```

---

## ⚡ Known Limitations

- **High resource usage** - DUI renders every frame
- **Direction accuracy** - Relies on GTA's native GPS which can be imprecise
- **Turns** - Turn curves are estimated, not path-accurate

---

## 🔧 Potential Improvements (For Contributors)

If you fork this project, consider:
- Implementing proper pathfinding node traversal
- Reducing DUI update frequency with interpolation
- Caching arrow positions
- Using native markers instead of DUI for better performance

---

## 📜 License & Credits

**Created by:** [Botz-Nithish](https://github.com/Botz-Nithish)

### Usage Terms:
- ✅ Free to use and modify
- ✅ Can be used in your own projects
- ⚠️ **Credits are required** - Please credit `Botz-Nithish` or link to this repo
- ❌ Do not claim as your own original work

---

## 🔗 Links

- **GitHub:** [https://github.com/Botz-Nithish/botz_routing](https://github.com/Botz-Nithish/botz_routing)
- **Demo Video:** [https://youtu.be/VCta3p7pWqQ](https://youtu.be/VCta3p7pWqQ)

---

<p align="center">
  <i>Use this as inspiration to build something amazing! 🚀</i>
</p>
