# Usable-machine status

Current as of 2026-08-03. This replaces the completed post-B0 experiment
ladder with a capability checklist.

| Capability | State | Next boundary |
|---|---|---|
| Untethered boot | Working | Maintain rollback and reproducible object builds |
| Panel and desktop | simpledrm, Xorg, i3/dwm working | GPU acceleration and backlight |
| Keyboard | Working with Norwegian layout | None for basic use |
| Trackpad | Not working | Resolve post-HIDF interface reset |
| CPU | Five-core RAM-root desktop proven; cpufreq working | MM/SMP stability, 14-core userspace, cpuidle |
| Network | WiFi and Bluetooth working | Persistent-root service integration |
| Power telemetry | Battery, AC, charger, temperature working | Suspend, lid/power actions, policy |
| Persistent storage | SD read/write and reboot persistence proven | Complete SD-root services |
| Internal NVMe | Brief Linux filesystem I/O | Fix first-CQ-wrap firmware assert |
| USB host | Not working | Reversible Type-C role/VBUS/PHY contract |
| Audio, camera, GPU | Not working | Later upstream-led stages |

## Immediate usable-system target

Ticket 204 completes the next practical milestone:

1. enrolled boot reaches the SD root;
2. a local console and SSH are reliable;
3. files persist across reboot;
4. WiFi and Bluetooth services start;
5. Xorg/i3 reaches the panel;
6. shutdown leaves both exFAT and the ext4 loop image clean.

Use `maxcpus=1` until the SD-root path is stable. Reintroduce additional CPUs
only in a separate MM/SMP test.

## Daily-driver exit

The machine becomes a reasonable unaccelerated daily driver when the persistent
root, trackpad, stable multi-core execution, network services, backlight, and
clean shutdown all work without a tether. GPU acceleration, audio, camera, and
suspend remain explicit later milestones.
