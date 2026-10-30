# Security

## Reporting a vulnerability

Please use GitHub's private reporting: **Security → Report a vulnerability** on this
repository. Don't open a public issue for security problems.

## Threat model and what Prism does

Prism is a local, single-user tool. It runs entirely as your user (no root, no setuid
helpers) and never listens on the network itself.

- **OpenRGB server.** The OpenRGB SDK has **no authentication**, so anything that can reach
  its port can control your devices. Prism's service starts it with
  `--server-host 127.0.0.1` (loopback only). OpenRGB versions without that flag (0.8 and older)
  listen on every interface by default, so `setup` refuses to start the server for them and
  asks you to update OpenRGB; `doctor` also fails if port 6742 is reachable from other hosts. If you
  already have your own `openrgb-server.service`, Prism leaves it alone, so make sure yours
  binds to `127.0.0.1` too. Check with `ss -ltn | grep 6742`.
- **Other local users.** On a shared machine, other local accounts can still connect to
  loopback port 6742. Prism targets single-user desktops.
- **Python dependency.** `setup` installs `openrgb-python` into a private virtual
  environment, pinned to an exact version **and SHA-256 hash**, with `--no-deps`, so a
  changed or tampered package is refused.
- **Files it writes.** `~/.config/omarchy-prism/`, `~/.local/state/omarchy-prism/`,
  `~/.local/share/omarchy-prism/`, two user systemd units, a theme hook, and a symlink in
  `~/.local/bin`. Everything `setup` creates carries a `Managed by omarchy-prism` marker,
  and `setup`/`uninstall` never overwrite or delete a file without it (for example your own
  `openrgb-server.service`).
- **Only elevated step.** Installing OpenRGB through `omarchy-pkg-add` (which asks for your
  sudo password) when it's missing. Nothing else uses sudo.
- **Untrusted input.** Paths are quoted wherever they are written into shell scripts or
  systemd units, commands are run without a shell, device names from hardware are shown as
  plain text, and the config and runtime files are validated when read.

## Caveat shared by all Omarchy plugins

Plugins run as unsandboxed code inside `omarchy-shell`. Read the code of anything you install.

## Checks

`python3 -m unittest discover -s tests -v` includes tests for hostile install paths,
hostile CLI arguments, malformed config and runtime files, hash-pinned installs, and the
"never touch files that aren't ours" rules.
