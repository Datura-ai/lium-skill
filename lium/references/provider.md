# Provider Journey for Agents

The whole provider path, written for an AI agent (Claude Code, Codex, …) that runs it unattended for a person who
owns GPU machines: install, sign in, add a node, diagnose it, fix it, list it on Secure, then read earnings and idle
pay. Every step has a copy-paste command, what success looks like in the JSON, and what to do on each failure. The
few steps only a person can do are listed in [One-time human steps](#one-time-human-steps), each with the exact
message to relay.

**Release status.** Commands and flags marked *(coming with the next CLI release)*, or `# lium#29x, not released yet` in
the code blocks, are in the open CLI pull requests
[lium#294](https://github.com/Datura-ai/lium/pull/294) (blocking reasons, `--fail-on-blocked`, `--until-clear`) and
[lium#295](https://github.com/Datura-ai/lium/pull/295) (register token, tier, pause, listing, earnings, idle pay,
ledger, API tokens, `portal login --email`, the Discord and e-mail handoffs, `lium mine --json`, the JSON envelope
and exit map below). lium 0.9.1 and older answer `No such command` or
`No such option` for them. Check what the installed CLI has with `lium provider <command> --help`.

## Contents

- [Two machines, one CLI](#two-machines-one-cli)
- [Environment variables](#environment-variables)
- [Output contract](#output-contract)
- [The journey](#the-journey)
- [Exit codes and error codes](#exit-codes-and-error-codes)
- [Blocking reasons](#blocking-reasons)
- [One-time human steps](#one-time-human-steps)

## Two machines, one CLI

- **The GPU host** is the machine being rented out. `lium mine` runs **on it**: it clones the executor, checks the
  ports, starts the executor container and runs the preflight checks. Host fixes (driver, sysbox, disk, reboot)
  happen here.
- **Anywhere** (the GPU host or a laptop): every `lium provider …` command talks to the provider portal and
  changes nothing on a host.

Install the CLI with the provider extras on each machine you drive:

```bash
pip install -U 'lium.io[provider]'
lium --version
```

## Environment variables

| Variable | What it does |
|---|---|
| `LIUM_OUTPUT=json` | Same as `--json` on every `lium provider` command and on `lium mine` *(coming with the next CLI release)*. lium 0.9.1 ignores it for provider commands: pass `--json`. |
| `LIUM_NONINTERACTIVE=1` | Agent mode without JSON output: no provider prompt reads stdin *(coming with the next CLI release; see [Agent mode](#agent-mode))*. |
| `LIUM_PROVIDER_ACK=1` | Answers the provider persona gate (the one-time "this changes your provider account" confirmation), like `--yes`. |
| `LIUM_PROVIDER_HOTKEY` | Hotkey **name** on the coldkey (with `LIUM_PROVIDER_COLDKEY`, the wallet name): sign in with the wallet on this machine. |
| `LIUM_PROVIDER_TOKEN` | A provider API token (`lpk_…`), sent as `Authorization: Bearer`; no wallet and no password needed *(coming with the next CLI release)*. |
| `LIUM_PROVIDER_PASSWORD` | The password `portal login --email` reads, so it never appears on the command line *(coming with the next CLI release)*. |
| `LIUM_PROVIDER_EMAIL` | Picks the stored e-mail session when several exist *(coming with the next CLI release)*. |

Keep secrets in the environment, not on argv. `lium mine -k` takes the hotkey's **SS58 address**, while
`lium provider -k` takes the hotkey **name**. They are different values.

## Output contract

- Success with `--json` is `{"ok": true, "data": …}` on stdout.
- *(coming with the next CLI release)* A failure is one envelope on **stdout** too:
  `{"ok": false, "error": {"code", "legacy_code"?, "message", "hint", "exit_code", "data"?, "request_id"?}}`, and the
  process exits with `exit_code`. Progress, when a command has any, goes to stderr as one JSON object per line.
- lium 0.9.1: a `--json` failure is `{"ok": false, "error": {"code", "message", "hint", "context"}}` on **stderr**,
  with an UPPER_CASE `code` and no `exit_code`; without `--json` it is text on stderr. Read stderr and the process
  exit status. `LIUM_OUTPUT=json` changes nothing there.
- `--json` and `--yes` work after the subcommand (`lium provider node listing --json`) or on the group
  (`lium provider --json node listing`).
- Branch on `error.code`, not on `message`. From the next CLI release codes are namespaced snake_case and never
  renamed once shipped (a portal refusal is `portal.<snake_case>`, the portal's own code), and the old UPPER_CASE
  code stays in `error.legacy_code`.

### Agent mode

*(coming with the next CLI release)* `--json`, `LIUM_OUTPUT=json` or `LIUM_NONINTERACTIVE=1` puts the provider
commands in agent mode. There a confirmation (the persona gate, or any command that changes something) never reads
stdin: it fails with `input.confirmation_required` (exit 2), and `--yes` or `LIUM_PROVIDER_ACK=1` is the way through.
Text mode (none of the three) behaves exactly as the released CLI: the prompt reads stdin, a piped `y` confirms and
a decline exits 1. Always run in agent mode and pass `--yes` (or set `LIUM_PROVIDER_ACK=1`) on commands that change
something; on lium 0.9.1 `--yes` and `LIUM_PROVIDER_ACK=1` answer the gate too.

## The journey

### 1. Sign in (pick one)

The account decides the path. A person who signs in to the portal with Google has no password: see
[Google-only account](#google-only-account).

```bash
# a) hotkey in a wallet on this machine
LIUM_PROVIDER_COLDKEY=my-wallet LIUM_PROVIDER_HOTKEY=my-hotkey lium provider portal login --json
# b) e-mail and password
LIUM_PROVIDER_PASSWORD="$PW" lium provider portal login --email owner@example.com --json  # lium#295, not released yet
# c) an API token: nothing to run, set it once
export LIUM_PROVIDER_TOKEN=lpk_...  # lium#295, not released yet
# check any of them
lium provider portal whoami --json  # with a token or an e-mail session: lium#295, not released yet
```

Success: `{"ok": true, "data": {"auth_method", "miner_id", "miner_hotkey", "email", …}}`, the account.
`data.auth_method` says which sign-in was used: `token`, `hotkey` or `email_session`. When several are set, a
command signs in with the first of: `LIUM_PROVIDER_TOKEN`, the hotkey, the `portal login --email` session. So unset
`LIUM_PROVIDER_TOKEN` when you mean to use another. With none, `whoami` answers `auth.not_signed_in` (exit 6): see
the [exit table](#exit-codes-and-error-codes). lium 0.9.1 has only a): there `whoami` needs the hotkey and answers no
`auth_method`. An unconfirmed e-mail account fails at `portal login`: see [E-mail confirmation](#e-mail-confirmation).

Once signed in with a) or b), mint a token so later runs need neither the wallet nor the password *(coming with the
next CLI release; until the portal serves API tokens it answers `portal.not_supported`, exit 3)*:

```bash
lium provider token create --name my-agent --scope read --scope node --scope tier --scope register --expires-days 30 --json --yes  # lium#295, not released yet
lium provider token list --json  # lium#295, not released yet
lium provider token revoke <TOKEN_ID> --json --yes  # lium#295, not released yet
```

`data` of `token create` has the secret **once**. Store it as `LIUM_PROVIDER_TOKEN`; `token list` never shows it.

### 2. Get a register token *(coming with the next CLI release)*

```bash
lium provider node register-token --json --yes  # lium#295, not released yet
```

Success: `data.token`, `data.expires_at` (one hour) and `data.install_command`, the line to run on the GPU host. The
token can only add a node to this account and watch its status. The portal's Add Node page shows the same line.

### 3. Set up the GPU host and register the node

On the GPU host, with the token from step 2:

```bash
lium mine --register "$REGISTER_TOKEN" --wait 45 --json  # --json: lium#295, not released yet
```

`--register` implies `--auto` (default ports: service 8080, SSH 2200). The CLI adds the node with the GPU model and
count `nvidia-smi` reports, the host's public IPv4 and the model's base price, then polls until the node is listed
or `--wait` minutes pass. `--price` and `--gpu-type` override the price and the portal GPU name. `--json` on
`lium mine` is *(coming with the next CLI release)*: each step is a line on stderr
(`{"event": "step", "step", "total", "code": "host.<step>", "status": "started|done|failed", …}`), and stdout
carries one result.

Success (exit 0): `data.node_id`, `data.node_url`, `data.status`, `data.listed: true`. Otherwise:

- **exit 11, `node.not_listed_yet`**: the node is registered but not listed yet. Go to step 4. In text mode (and on
  0.9.1) this case is exit 2.
- **exit 1, `node.offline` / `node.validation_failed`**: the portal names a fix in `data.fix`. Go to step 4.
- **exit 1, `host.*`**: a setup step failed on the host (`host.docker_missing`, `host.nvidia_driver_missing`,
  `host.port_in_use` with `data.port` and `data.owner`, `host.preflight_failed` with `data.verdict`, …). Fix the host
  and re-run the same command. A node that is already registered is not added twice.
- **exit 2, `input.register_token_invalid`**: the token expired or is malformed; nothing on the host was touched.
  Mint a new one (step 2).

Without a register token (hotkey accounts), start the executor, then add it from anywhere:

```bash
lium mine -k <HOTKEY_SS58> --auto
lium provider node add --gpu-type H100 --gpu-count 8 --ip 203.0.113.7 --port 8080 --json --yes
```

`node add` without `--price` takes the model's default price, as the portal's Add Node form does.

### 4. Diagnose

```bash
# every own node: listing_state (rented, listed, hidden, offline, validating), gpu_count, rented_gpu_count, hidden_reasons
lium provider node listing --json  # lium#295, not released yet
# one node, with blocking_reasons; exit 10 while anything blocks
lium provider node get "$NODE" --json --fail-on-blocked  # lium#294, not released yet
# which validator step the node is on, and the last run's timeline
lium provider node status "$NODE" --json
```

`node get` puts every reason the node is kept off the listing or out of idle pay in `data.blocking_reasons`
*(coming with the next CLI release)*. With `--fail-on-blocked` a blocked node is one envelope:
`{"ok": false, "error": {"code": "node.blocked.<first reason's code>", "exit_code": 10, "data": <the node>}}`.
Each reason has `kind`, `code`, `gating`, `message`, `measured`, `required`, `fix`, `fix_command`, `verify_command`,
`requires` and `docs_url`. What to do per code is in [Blocking reasons](#blocking-reasons).

Read `gating` from the reason; keep no list of your own. A reason with `kind` `availability` or `last_error` blocks
renting whatever its `gating`. An `idle_pay` reason with `gating: false` blocks nothing: the node only earns no idle
pay, and no action is needed. Until the portal serves the list, the CLI builds it from the validator's last error,
the listing's hidden reasons and the idle-pay reasons, and marks those nodes `"blocking_reasons_source": "cli_fallback"`
(each of those entries names its origin in `source`). Every reason carries `requires`; a reason nobody has said the
needs of (a last error, a hidden reason, a code the CLI does not know, or a portal reason sent without `requires`)
has `"requires_unknown": true`, and the text panel prints `Requires: unknown — hand this step to a person` above
its fix.

### 5. Fix, then verify

For each gating reason, decide first whether you may fix it at all.

**Stop and hand over** ([Reboots and other host steps](#reboots-and-other-host-steps)) when any of these holds:

- `requires` contains `reboot` or `no_rentals`;
- `requires_unknown` is `true` (treat a reason with no `requires` key at all the same way);
- the fix needs `sudo` on a host you cannot `sudo` on.

The one exception: a fix that is only a `lium provider` command (`node min-gpu set`, `node update-price`) changes
nothing on the host and is yours to run.

Never reboot, never restart the Docker daemon (`systemctl restart docker` or the like), and never install or upgrade
a driver, on your own, whatever `fix` says: each of them can end the rentals on the node.

**Before a `no_rentals` fix**, read the node's listing, then decide whether to pause new rentals:

```bash
lium provider node listing "$NODE" --json  # lium#295, not released yet
```

Read two things from that row:

- **Has a rental**: `data.rented_gpu_count` is above 0, or `data.listing_state` is `rented`. Test both: a partly
  rented node whose free GPUs are still offered reads `listing_state: "listed"` with `rented_gpu_count` above 0. The
  row always has the key; when it is `null` (an older portal), go by `listing_state` alone.
- **Already paused**: `data.hidden_reasons` has an entry with `code` `NEW_RENTALS_PAUSED`. The portal lists it
  whenever new rentals are paused on the node, rented or not.

Then:

- **No rental**: the node is free. Do not pause it, and do not resume it later. Go straight to the hand-over below.
- **A rental, already paused**: do not call `node pause`, and do not resume the node later: the pause was not yours.
  Wait for the rental to end, as below.
- **A rental, not paused**: pause new rentals (the reason's `fix` starts with that step, worded for the portal's
  Pause New Rentals button; `node pause` is the same action), then wait for the rental to end:

```bash
lium provider node pause "$NODE" --json --yes  # lium#295, not released yet
```

Record that this flow paused the node only when `pause` answered exit 0 here; only then do you resume it below. If
`pause` refuses the node as not rented (exit 3, `portal.node_not_rented`, or `portal.request_rejected` with an
`error.message` saying the node must be rented), the rental ended between the two calls: the node is free and you
did not pause it.

The wait is bounded: re-read `listing` every 10 minutes, for at most 6 hours, until `data.rented_gpu_count` is 0 (or,
when it is `null`, `data.listing_state` is not `rented`). If the rental is still running then, hand over with this
message:

> Node <node_id> needs a fix that interrupts rentals: <fix>. New rentals are paused, but the current rental is still
> running after 6 hours. Please decide when to do the fix, then tell me when it is done.

Once the node is free, hand the fix itself over as above. After the person has done it and the node is clear
(below), open it to rentals again, but only if this flow paused it. A pause that was there before is the owner's
choice: leave it.

```bash
lium provider node resume "$NODE" --json --yes  # lium#295, not released yet
```

**Everything else** you may fix: run `fix_command` when the reason has one, otherwise do what `fix` says, then run
`verify_command` when present. Then watch until the node is clear:

```bash
# one JSON object per refresh; exit 0 once no gating reason is left, 10 at the timeout
lium provider node status "$NODE" --json --watch --until-clear --timeout 1800  # lium#294, not released yet
```

The verdict lands when the validator publishes its next cycle, so a clear node can take several minutes to show as
clear. On exit 10, read `error.data` again: the reason is still there, or a new one appeared.

### 6. List on Secure *(coming with the next CLI release)*

```bash
lium provider node tier eligibility "$NODE" --json  # lium#295, not released yet
lium provider node tier set "$NODE" secure --json --yes  # lium#295, not released yet
lium provider node listing "$NODE" --json  # lium#295, not released yet
```

`eligibility` answers `data.allowed` and `data.blockers` (`{code, message}`: `rented`, `cluster_member`). A refused
change is `portal.tier_change_blocked` (exit 3) with the blocker in `error.data`: wait until the blocker clears
(`rented`: the rental ends; `cluster_member`: the node leaves its cluster). Done when `listing` shows `data.listing_state: "listed"`.

Other node changes: `lium provider node update-price "$NODE" --price 1.85 --json --yes`,
`lium provider node pause|resume "$NODE" --json --yes` (pause refuses an idle node with `portal.node_not_rented`),
`lium provider node min-gpu set "$NODE" 4 --json --yes`.

### 7. Earnings and idle pay *(coming with the next CLI release)*

```bash
lium provider earnings --from 2026-09-01 --json  # lium#295, not released yet
lium provider earnings --emissions --json  # lium#295, not released yet
lium provider idle-pay --json  # lium#295, not released yet
lium provider idle-pay "$NODE" --json  # lium#295, not released yet
lium provider ledger --from 2026-09-01 --json  # lium#295, not released yet
```

`earnings` is rental earnings per UTC day (default: the last 7 days); `--emissions` is the daily incentive instead,
and `--node` (repeatable) narrows it. `idle-pay` gives, for each node with a free GPU, `idle_pay`: `paid`,
`not_paid` (with `idle_pay_reasons`, the validator's codes, which the [Blocking reasons](#blocking-reasons) table
explains), `rented_last_cycle` or `unknown` (no validator cycle yet); a fully rented node has `idle_pay: null`. The
top level has `idle_pay_usd` over `window_days` and the `idle`, `idle_earning` and `idle_unpaid` counts. Idle pay
needs a linked Discord account: see [Discord linking](#discord-linking).

## Exit codes and error codes

Branch on `error.code`; the exit code is the coarse class. Under `--json` or `LIUM_OUTPUT=json` every provider
error exits by this one map, whatever its origin, and an old UPPER_CASE code is kept only in `error.legacy_code`
*(coming with the next CLI release)*.

| Exit | Codes | Meaning | What the agent does |
|---|---|---|---|
| 0 | | ok | Continue. |
| 1 | `host.*`, `node.offline`, `node.validation_failed` | A step failed, or the portal names a fix | Read `error.message` and `error.data`; fix the host or the node, then re-run the same command. |
| 2 | `input.confirmation_required`, `input.input_required`, `input.arg_invalid`, `input.register_token_invalid`, `input.hotkey_conflicts_with_token` | A value or a confirmation nobody could give | Add what `error.hint` names (`--yes` or `LIUM_PROVIDER_ACK=1`, `-k`, `LIUM_PROVIDER_PASSWORD`, a new register token) and re-run once. Never retry unchanged. `input.arg_invalid` is a bad argument value, or a command that needs the hotkey itself (`lium provider status`, `portal login` without `--email`, `portal logout`) run without one; it does not mean "not signed in" (that is `auth.not_signed_in`, exit 6). |
| 3 | `portal.<detail.code>`, `portal.not_supported` | The portal refused or failed the call | `portal.not_supported` on `config connect-discord` or `portal confirm-email` (with `data.legacy_flow: true`): follow the old flow in [One-time human steps](#one-time-human-steps); do not stop there. On any other command the portal does not serve this route yet: stop using that command. Other codes: act on `error.message`/`error.data`; a 5xx may be retried up to 3 times with backoff. |
| 4 | `net.unreachable`, `ssh.*` | Nothing answered | Check the network and `--portal-url`; retry with backoff (30 s, 60 s, 120 s). |
| 5 | `node.not_found`, `portal.executor_not_found`, `auth.wallet_not_found`, `host.uuid_not_found`, any other `*_not_found` code or portal 404 | Something the command names does not exist | By code. `auth.wallet_not_found`: this machine has no wallet by those names; fix `LIUM_PROVIDER_COLDKEY` / `LIUM_PROVIDER_HOTKEY` (the wallet and hotkey **names**) or use another sign-in, then re-run once. `host.uuid_not_found`: the executor installer on the host did not report an executor id, so the host setup did not finish; read `error.message`, fix the host and re-run step 3. Any other: the node is not on this account; re-read the ids with `lium provider node listing --json`. |
| 6 | `auth.not_signed_in`, `auth.*` (not `auth.refresh_race` or `auth.wallet_not_found`), `portal.api_token_needs_session`, `portal.api_token_scope_missing`, a portal 401/403 | Not signed in, signed out, expired or not allowed | `auth.not_signed_in`: nothing is signed in, and every provider command that needs a sign-in answers it under `--json`. Follow `error.hint`: set `LIUM_PROVIDER_TOKEN`, run `portal login --email`, or set a hotkey ([step 1](#1-sign-in-pick-one)). If `error.data.session_email` is present, that e-mail session has ended: re-run `lium provider portal login --email <that address> --json`. Other codes: sign in again the same way (`lium provider portal login --force --json` for a hotkey) or use a token with the right scope. Do not loop. |
| 7 | `portal.rate_limited` (a portal 429), `auth.refresh_race` | Rate limit, or another `lium provider` process is refreshing the token | Retry: after 60 s on a rate limit, after a few seconds on `auth.refresh_race`. |
| 10 | `node.blocked.<code>` | The node has a gating blocking reason | Look up `<code>` in [Blocking reasons](#blocking-reasons), fix it, then `node status --watch --until-clear`. |
| 11 | `node.not_listed_yet` | Registered and waited for, not listed yet | Diagnose (step 4); nothing is lost, the node stays registered. |
| 12 | `human.handoff_required`, `human.handoff_expired` | A person has to act | Relay `error.data.message_for_human` ([One-time human steps](#one-time-human-steps)), wait for the person, then re-run. A `--wait` that timed out is `human.handoff_required` with `error.data.waited_s`: the person has not finished; a re-run asks for a new code, so relay the new message. |

Text mode (no `--json`, no `LIUM_OUTPUT=json`) keeps today's provider exit numbers: 1 argument, 2 auth, 3 portal,
5 SSH, 6 config missing, 7 token-cache race; so does lium 0.9.1 in every mode. The CLI's `docs/exit-codes.md`
shows both maps.

## Blocking reasons

The reason's own `requires` and `requires_unknown` decide ([stop rule](#5-fix-then-verify)); the `requires` column
shows what comes with each code. It names what the fix needs: `sudo` (root on the GPU host), `reboot` and
`no_rentals` (both a hand-over); "none" is an empty list.
"Verify" always ends with `lium provider node status "$NODE" --json --watch --until-clear --timeout 1800` (`--until-clear`: lium#294, not released yet).

**The validator's idle-pay reasons** (`kind: idle_pay`, the codes in `idle_pay_reasons`):

| `code` | Meaning | `requires` | Fix, then verify |
|---|---|---|---|
| `nvidia_driver_below_minimum` | The NVIDIA driver is older than the network minimum (580.65.06 today) | sudo, reboot, no_rentals | Hand over: upgrade the driver, reboot, restart the executor (`docker compose up -d` in `neurons/executor`). |
| `sysbox_not_enabled` | The executor does not run the sysbox runtime | sudo, no_rentals | Hand over: install and enable sysbox, restart the executor. |
| `insufficient_disk_for_vram` | Total disk is below the required share of GPU VRAM (`measured` vs `required`, in GB) | sudo, no_rentals | Hand over: give the host at least `required` GB of disk. |
| `flagship_without_ncu_or_split` | An idle 8x flagship offers no NCU profiling, GPU splitting or confidential computing | sudo, reboot, no_rentals | Yours, no reboot: `lium provider node min-gpu set "$NODE" <n> --json --yes` with `n` below the full node. Otherwise hand over: open the profiling counters (`NVreg_RestrictProfilingToAdminUsers=0`, then reboot), or run in a confidential VM. |
| `cannot_apply_gpu_power_cap` | The executor container cannot run `nvidia-smi -pl` | none; sudo, no_rentals when the node container runs under sysbox | `docker compose pull && docker compose up -d` in `neurons/executor`; a custom compose needs `privileged: true`. |
| `outdated_executor_image` | The executor image is not the current release | none | Do what the reason's `fix` says (the validator's text): on a standard stack, check that `executor-executor-runner-1` and `executor-watchtower-1` are running (`docker ps`) so Watchtower redeploys the current image; if auto-update stopped, hand over with the `docs_url` (https://docs.lium.io/providers/nodes/gpu-power-cap#the-standard-stack-which-stopped-updating). |
| `price_above_market_p90_soft_limit` | The price is above the market's soft limit | none | `lium provider node update-price "$NODE" --price <required> --json --yes` (the limit is in `required`). |
| `port_limited_remainder` | A partly rented node has too few free ports for its free GPUs | sudo | Open more ports on the host, or wait for the rental to end. |
| `miner_default_job` | The node runs the owner's own default job | none | Stop that job on the host. |
| `provider_discord_not_connected` | No Discord linked: no idle pay, no subnet incentive | none (a human step) | [Discord linking](#discord-linking), then `lium provider config show --json` shows `data.discord_connected: true`. |
| `new_rentals_paused` | New rentals are paused on this node (the owner's choice; not gating) | none | Only if the owner wants it: `lium provider node resume "$NODE" --json --yes`. |
| `spot_tier` | Spot-tier nodes earn no subnet incentive (not gating) | none | Only if the owner wants it: [step 6](#6-list-on-secure-coming-with-the-next-cli-release). |
| `banned_network_abuse` | The node is banned for network abuse | none (a human step) | Human step: the owner contacts Lium support. Do not retry. |
| `gpu_model_not_eligible_for_unrented_incentive` | This GPU model is not in the idle-pay program (`gating: false`) | none | No action: the model earns from rentals only. |
| `no_unrented_capacity_for_gpu_count` | No idle-pay room for this node size this cycle (`gating: false`) | none | No action: rentals still pay, and room opens as the market moves. |

**Reachability** (`kind: availability`, the listing's `hidden_reasons`) always blocks renting. Built by the CLI,
these come with `requires_unknown: true`: hand the fix over. Fix one yourself only when the portal serves the reason
with a `requires` the [stop rule](#5-fix-then-verify) lets through.

| `code` | Meaning | Fix, then verify |
|---|---|---|
| `NOT_RESPONDING` | The validator cannot reach the executor | Start the executor (`docker compose up -d` in `neurons/executor`) and open its port to the internet. |
| `NOT_ACTIVE`, `NOT_VERIFIED` | The node has not passed a validator check yet | Wait for the next check, or fix the error `node status` reports. |
| `DISK_TOO_FULL` | Disk more than 90% used | Free disk until at most 90% is used, within the limits below. |
| `DISK_FREE_TOO_LOW` | Too little free disk | Free disk within the limits below; a larger disk is a hand-over. |
| `DISK_NOT_REPORTED` | The executor does not report its disk | Update and restart the executor. |
| `NETWORK_TOO_SLOW` | The uplink is below the minimum | Move the node to a faster uplink. |
| `GPU_COUNT_UNKNOWN` | The validator could not read the GPUs | Restart the executor. |

Freeing disk unattended: delete only logs, caches and files the owner named. Never delete Docker volumes, images or
containers (no `docker system prune`, no `docker volume rm`): a rental may be using them. If that does not free
enough, hand over.

`NEW_RENTALS_PAUSED`, `RECLAIMING`, `WHOLE_HOST_ONLY` and `SPLIT_MINIMUM_NOT_MET` hide the node without blocking it:
they are the owner's choice or the normal shape of a partial rental.

**The validator's last error** (`kind: last_error`) always blocks renting. `code` is the validator's reason code and
`fix` its own remediation. Built by the CLI it has `requires_unknown: true`: relay `fix` in the hand-over message.

## One-time human steps

These steps need a person once. Stop, send the message exactly as written (fill in the `<…>` values), wait for the
answer, then run the command under "After".

*(coming with the next CLI release)* In agent mode, or with `--wait`, the CLI asks the portal for a handoff: one URL
plus a short code. (Text mode without `--wait` runs `connect-discord`'s browser flow, as the released CLI does;
`confirm-email` is always a handoff.) Without `--wait` the command exits 12 with `{"ok": false, "error": {"code": "human.handoff_required", "exit_code": 12, "data": {"step",
"handoff_id", "handoff_url", "code", "expires_at", "message_for_human"}}}`. Relay `data.message_for_human` verbatim.
With `--wait [--timeout N]` the command first prints the same data as one `{"event": "handoff", …}` line on stderr
(relay its `message_for_human`), then polls: exit 0 when the person is done, exit 12 with `human.handoff_expired`
when the code expires (run it again for a new code), exit 12 with `human.handoff_required` and `data.waited_s` when
`--timeout` passes first (with `--wait`, `--timeout` counts only when given; otherwise it waits until the code
expires). A portal without handoff sessions answers exit 3, `portal.not_supported`, with `data.legacy_flow: true` and
`data.legacy_browser_url` in agent mode: that link is the one-time step, see each section.

**Which form to run.** With `--wait`, the message to relay arrives on **stderr while the command is still running**;
stdout gets its one envelope only when the command ends. If your shell tool shows output only when a command exits,
or stops a command after a few minutes, run the step **without `--wait`**: it exits 12 at once with the message in
`error.data` on stdout. Relay it, then wait for the person without running the step again: every run asks the portal
for a new code, which replaces the one you relayed. Each section says how to check the step afterwards. Use `--wait`
only when your tool shows stderr as it arrives, with a `--timeout` below the tool's own time limit.

### Discord linking

Required for idle pay (`provider_discord_not_connected`).

```bash
# the message at once (exit 12): for tools that show output only at exit
lium provider config connect-discord --json  # the handoff: lium#295, not released yet
# or relay the stderr handoff line while this waits for the person
lium provider config connect-discord --json --wait --timeout 900  # --wait: lium#295, not released yet
```

- **Handoff** (exit 12 at once without `--wait`, or the stderr `handoff` line with it): relay
  `message_for_human`. With `--wait`, exit 0 (`data.discord_connected: true`) means linked; without it, check as
  below.
- **exit 3, `portal.not_supported` with `data.legacy_flow: true`**: not a reason to stop. Relay, with `<url>` =
  `data.legacy_browser_url`:

> To get idle pay for your Lium provider nodes, link your Discord account once: open <url> in a browser signed in to
> your Lium provider account, sign in to Discord and approve Lium. Tell me when you are done.

- **lium 0.9.1**: run `lium provider config connect-discord --json --no-wait` and relay the same message with
  `<url>` = `data.authorization_url`.

After a relay without `--wait`, the legacy relay or the 0.9.1 relay, poll every 30 s for up to 15 minutes until
`data.discord_connected` is `true` (this reads the account and asks for no new code):

```bash
lium provider config show --json
```

Once Discord is linked, `connect-discord --json` answers exit 0 with `data.already_done: true`.

### E-mail confirmation

Confirms the e-mail of an account created with e-mail and password. It runs once signed in (hotkey, API token or
an e-mail session); there is no code option, only the handoff:

```bash
# the message at once (exit 12): for tools that show output only at exit
lium provider portal confirm-email --json  # lium#295, not released yet
# or relay the stderr handoff line while this waits for the person
lium provider portal confirm-email --json --wait --timeout 900  # lium#295, not released yet
```

- **Handoff**: relay `message_for_human`; the person enters the code in the portal and follows the mailed link.
  With `--wait`, exit 0 means confirmed. Without it, wait until the person says they are done, then run
  `confirm-email --json` once: exit 0 with `data.already_done: true` means confirmed; exit 12 again means it is not,
  so relay the new message.
- **exit 3, `portal.not_supported` with `data.legacy_flow: true`**, lium 0.9.1, or `portal login --email` refused
  because the e-mail is not confirmed (the refusal says so in `error.message`). Relay:

> Your Lium provider account <email> is not confirmed yet. Please open the confirmation e-mail from Lium and click its
> link (check spam if it is not in your inbox). Tell me when you are done.

After, sign in again:

```bash
LIUM_PROVIDER_PASSWORD="$PW" lium provider portal login --email <email> --json  # lium#295, not released yet
```

### Google-only account

An account that signs in only with Google has no password, and an agent does not sign in with Google. Relay:

> Your Lium provider account signs in with Google, which I cannot do for you. Please sign in at
> https://provider.lium.io, open Add Node, and send me the install command it shows (it starts with `curl -fsSL`
> and contains `--register`; it works for one hour).

After, run that line on the GPU host, or pass its token to `lium mine --register "$REGISTER_TOKEN" --json`, and
continue at step 3. For the later steps (diagnose, tier, earnings) ask for an API token instead, once the portal
serves them *(coming with the next CLI release)*:

> Please create a Lium provider API token for me on a machine where you are signed in to the Lium provider CLI:
> `lium provider token create --name my-agent --scope read --scope node --scope tier --scope register --json --yes`,
> and send me the token it prints (it is shown once). I will keep it only as LIUM_PROVIDER_TOKEN, and you can revoke
> it at any time with `lium provider token revoke`.

After: `export LIUM_PROVIDER_TOKEN=lpk_...` (lium#295, not released yet), then
`lium provider portal whoami --json` answers `data.auth_method: "token"`.

### Reboots and other host steps

Every fix the [stop rule](#5-fix-then-verify) names is a person's step: `requires` with `reboot` or `no_rentals`,
`requires_unknown: true`, `sudo` you do not have, new hardware, a faster uplink or a support ticket. Never reboot or restart the Docker daemon unattended. Relay:

> Node <node_id> on <host> needs you for one step: <fix>. I stopped here because it needs <a reboot | an interruption
> of rentals | root access | new hardware | Lium support | a person's judgement>. Please do it, then tell me when the machine is back up.

After the person answers, check the node, then resume rentals if you paused them (step 5):

```bash
lium provider node status "$NODE" --json --watch --until-clear --timeout 1800  # lium#294, not released yet
```
