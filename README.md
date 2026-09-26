# HuntiX

Automated URL / endpoint reconnaissance. HuntiX combines passive archive
sources with active crawlers and content discovery tools, then merges and
de-duplicates everything into one clean output file.

```
  ██╗  ██╗ ██╗   ██╗ ███╗   ██╗ ████████╗ ██╗ ██╗  ██╗
  ██║  ██║ ██║   ██║ ████╗  ██║ ╚══██╔══╝ ██║ ╚██╗██╔╝
  ███████║ ██║   ██║ ██╔██╗ ██║    ██║    ██║  ╚███╔╝ 
  ██╔══██║ ██║   ██║ ██║╚██╗██║    ██║    ██║  ██╔██╗ 
  ██║  ██║ ╚██████╔╝ ██║ ╚████║    ██║    ██║ ██╔╝ ██╗
  ╚═╝  ╚═╝  ╚═════╝  ╚═╝  ╚═══╝    ╚═╝    ╚═╝ ╚═╝  ╚═╝
                        v2.0 - Automated URL Recon
```


## Features

| Tool | Type | Notes |
|---|---|---|
| `gau` | Passive | Aggregates multiple archive sources |
| `waybackurls` | Passive | archive.org |
| `cdx` | Passive | Wayback Machine CDX API (no install needed, uses `curl`) |
| `katana` | Active | JS-aware crawler |
| `gospider` | Active | Fast concurrent crawler |
| `dirsearch` | Active | Directory / backup-file brute-forcer |
| `urlscan` | Passive | urlscan.io API (works without a key, better with one) |

- Merges and de-duplicates all results into one master file (`anew`)
- Per-domain, per-tool result files when scanning a list
- Dependency check on startup — tells you exactly what's missing instead of
  silently returning 0 results
- Full `debug.log` per run so tool errors are never silently swallowed
- Supports a single domain or a file with a list of domains

## Requirements

| Tool | Install |
|---|---|
| [gau](https://github.com/lc/gau) | `go install github.com/lc/gau/v2/cmd/gau@latest` |
| [waybackurls](https://github.com/tomnomnom/waybackurls) | `go install github.com/tomnomnom/waybackurls@latest` |
| [katana](https://github.com/projectdiscovery/katana) | `go install github.com/projectdiscovery/katana/cmd/katana@latest` |
| [gospider](https://github.com/jaeles-project/gospider) | `go install github.com/jaeles-project/gospider@latest` |
| [dirsearch](https://github.com/maurosoria/dirsearch) | `pip install dirsearch` (or clone + `pip install -r requirements.txt`) |
| [anew](https://github.com/tomnomnom/anew) | `go install github.com/tomnomnom/anew@latest` |
| jq | `apt install jq` / `brew install jq` |
| curl | Usually pre-installed |

HuntiX checks for all of these on startup and tells you what's missing
rather than failing silently.

## Installation

```bash
git clone https://github.com/Kerolos-Iskander1/huntix.git
cd huntix
chmod +x huntix.sh
sudo mv huntix.sh /usr/local/bin/huntix
```

## Usage

```bash
huntix target.com                 # run every tool against one domain
huntix domains.txt                # run every tool against each domain in a file
huntix target.com -t gospider     # run only one tool
huntix -h                         # full help
```


## Configuration (optional)

HuntiX reads settings from `~/.config/huntix/config.yaml`. Right now it
only looks for `urlscan_api_key` (used to get full, non-rate-limited results
from urlscan.io instead of public mode), but this file is meant to grow into
a general config as more options get added.

```bash
mkdir -p ~/.config/huntix
cp config.yaml.example ~/.config/huntix/config.yaml
nano ~/.config/urlhunter/config.yaml  # and add your Api-key
```


## Contributing

Issues and PRs are welcome. Please don't submit changes that add scanning
against targets without consent, or that weaken the authorization checks.

## License

[MIT](LICENSE)
