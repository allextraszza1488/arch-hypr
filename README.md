# arch-hypr

Portable Arch + Hyprland installer. `install.sh` probes the machine and
runs the module plan for real: packages via `pacman_needed`, dots from
`config/`, snapper/makepkg/reflector with `backup_file` before any `/etc`
edit. Host-specific bits (monitor pin, reflector `--country`) live under
`host/<name>/` and are applied only with `--host`.

Do not run as root. `install.sh` refuses uid 0 — rerun as yourself; the
modules sudo internally when they touch `/etc` or pacman.

## Probe a live USB (no install)

`lib/detect.sh` is standalone and writes nothing. From a live USB:

```bash
curl <raw-url>/lib/detect.sh | bash
```

Same thing through the installer, or locally:

```bash
./install.sh --probe
bash lib/detect.sh --probe
```

Prints `key=value` lines (`nproc`, `root_fs`, `bootloader`, `chassis`,
`nvidia`, `amd`, `intel`, `pci`) and exits 0.

GPU detection greps `lspci -nn` for PCI class `[0300]` (VGA) **or**
`[0302]` (3D controller). Matching only "VGA" misses NVIDIA on Optimus
laptops. Vendors: NVIDIA `10de`, AMD `1002`, Intel `8086`.

## Installer flags

```bash
./install.sh                  # run the default module plan
./install.sh --host NAME      # host overlay (e.g. f3nt-desktop)
./install.sh --with steam,snapshots
./install.sh --without steam,suspend
./install.sh --undo           # restore every file recorded in the manifest
```

`--with` / `--without` take a comma-separated list. Names can be the short
form (`steam`) or the numbered form (`90-steam`).

Default plan, in order:

| module | when |
| --- | --- |
| `00-preflight` | always |
| `10-hypr-stack` | always |
| `20-gpu` | always (packages follow the probe) |
| `30-dots` | always |
| `40-look` | always |
| `50-snapshots` | only if root is btrfs |
| `60-suspend` | only if NVIDIA is present (s2idle; deep S3 hangs Blackwell) |
| `70-tuning` | always |
| `80-security` | always |
| `90-steam` | always |

`--with` forces a skipped module back on; `--without` drops one.

Shared dots live in `config/` (hypr, kitty, fish, waybar, fuzzel, nvim,
scripts, …). `config/hypr/hyprland.lua` `pcall(dofile)`s
`~/.config/hypr/host.lua`; that file is installed from `host/<name>/`
when `--host` is set, and is simply missing otherwise (no monitor pin).

## Undo

`backup_file` copies `file` to `file.bak.TIMESTAMP` and appends the
original path to `$MANIFEST_FILE` (default
`~/.local/state/arch-hypr/manifest.txt`). `--undo` reads that manifest
and restores every `.bak`.

60-suspend, 80-security, and 90-steam still print the plan only.
