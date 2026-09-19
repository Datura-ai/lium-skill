# Registry entry for the Lium docs MCP server

`server.json` in this folder is the [official MCP Registry](https://registry.modelcontextprotocol.io)
entry for the remote MCP endpoint of the Lium documentation site. Nothing in this folder runs a
server; the server is `https://docs.lium.io/mcp` (Streamable HTTP, JSON-RPC 2.0), documented at
<https://docs.lium.io/developers/mcp>. This folder only holds the metadata a human publishes.

What the endpoint exposes (verified against `tools/list` on 19 Sep 2026; `serverInfo.name`
is `lium-docs`, version `1.0.0`):

| Tool | Arguments | Purpose |
|------|-----------|---------|
| `search` | `query` (required), `audience` (`providers` \| `validators` \| `pod-users` \| `developers`), `limit` (1–50, default 10) | Full-text search over docs.lium.io |
| `read_page` | `url_or_slug` (full URL, absolute slug or basename) | Raw Markdown source of one docs page |

It is the **docs** server only. The platform API (create pods, manage volumes, …) is not an MCP
server; agents call it through the CLI/SDK described in `lium/SKILL.md` or the REST API at
`https://lium.io/api/openapi.json`.

## The two possible names

The registry ties the server name to how the publisher authenticates
([authentication guide](https://github.com/modelcontextprotocol/registry/blob/main/docs/modelcontextprotocol-io/authentication.mdx)):

| `name` in `server.json` | Login that grants it | Who can do it |
|---|---|---|
| `io.lium.docs/lium-docs` (as committed) | `mcp-publisher login dns --domain lium.io …` — DNS auth grants `io.lium/*` **and** every subdomain `io.lium.*` | Someone who can add a TXT record at the **apex** of `lium.io` |
| `io.lium/lium-docs` | DNS auth as above, or `mcp-publisher login http --domain lium.io …` (a file at `https://lium.io/.well-known/mcp-registry-auth`; HTTP auth grants `io.lium/*` only, no subdomains) | Someone who can add a DNS record or a static file on lium.io |
| `io.github.Datura-ai/lium-docs` | `mcp-publisher login github` — grants `io.github.<user>/*` and `io.github.<org>/*` for orgs where the user is an **Owner** | An Owner of the `Datura-ai` GitHub organisation |

Both `io.lium.docs/lium-docs` and `io.github.Datura-ai/lium-docs` pass `mcp-publisher validate`.
Pick one, edit `name` if needed, then follow the matching login below. A domain name is the
better long-term choice (it survives an org rename and reads as the vendor); the GitHub name
needs no DNS change and can be published immediately by an org owner.

## Publishing (human steps)

### 0. Install the publisher

```bash
curl -L "https://github.com/modelcontextprotocol/registry/releases/latest/download/mcp-publisher_$(uname -s | tr '[:upper:]' '[:lower:]')_$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" | tar xz mcp-publisher && sudo mv mcp-publisher /usr/local/bin/
# or: brew install mcp-publisher
```

### 1. Validate

```bash
cd mcp
mcp-publisher validate server.json
# expected: ✅ server.json is valid
```

### 2a. Login with DNS (for `io.lium.docs/…` or `io.lium/…`)

```bash
MY_DOMAIN="lium.io"
openssl genpkey -algorithm Ed25519 -out key.pem          # keep key.pem out of git
PUBLIC_KEY="$(openssl pkey -in key.pem -pubout -outform DER | tail -c 32 | base64)"
echo "${MY_DOMAIN}. IN TXT \"v=MCPv1; k=ed25519; p=${PUBLIC_KEY}\""
```

Add that TXT record on the apex `lium.io` (not under a selector such as `_mcp-auth.lium.io`),
wait for it to propagate, then:

```bash
PRIVATE_KEY="$(openssl pkey -in key.pem -noout -text | grep -A3 "priv:" | tail -n +2 | tr -d ' :\n')"
mcp-publisher login dns --domain "${MY_DOMAIN}" --private-key "${PRIVATE_KEY}"
```

(Requires OpenSSL 3; on macOS use Homebrew's `openssl@3`. Google KMS / Azure Key Vault variants
are in the authentication guide linked above.)

### 2b. Login with GitHub (for `io.github.Datura-ai/…`)

```bash
mcp-publisher login github      # device-code flow in the browser; must be an Owner of Datura-ai
```

### 3. Publish

```bash
mcp-publisher publish server.json
# expected: ✓ Server io.lium.docs/lium-docs version 1.0.0
curl "https://registry.modelcontextprotocol.io/v0.1/servers?search=lium-docs"
```

To publish a new version later, bump `version` (semver, no ranges) and run `publish` again.

## Smithery (smithery.ai)

Smithery lists remote servers by URL ("bring your own hosting"; docs:
<https://smithery.ai/docs/build/publish>). Requirements: Streamable HTTP transport, public HTTPS URL,
and the scanner (`User-Agent: SmitheryBot/1.0`) must not be blocked by the CDN. Fields to submit:

| Field | Value |
|---|---|
| Form | <https://smithery.ai/new> — "Enter your server's public HTTPS URL" |
| Server URL | `https://docs.lium.io/mcp` |
| Namespace / name | `@<org>/lium-docs` — the namespace Smithery assigns to the GitHub org/user the human logs in with (expected `@datura-ai/lium-docs`) |
| Display name | Lium Docs |
| Description | Search and read the Lium (lium.io) GPU marketplace docs: renting pods, CLI, SDK, API, providers. |
| Homepage | <https://docs.lium.io> |
| Repository | <https://github.com/Datura-ai/lium-skill> |
| Auth | none (public endpoint, no key or OAuth) |
| Config schema | none |

CLI equivalent (after `smithery auth login`):

```bash
smithery mcp publish "https://docs.lium.io/mcp" -n @<org>/lium-docs
```

After publishing, open the server's Settings → Verification page for the official-vendor badge.
If the scan reports a 403, allow `SmitheryBot` at the CDN in front of docs.lium.io or serve a
static card at `https://docs.lium.io/.well-known/mcp/server-card.json` (format on the Smithery page).

## Notes for the reviewer

- `repository` points at this repo (`subfolder: mcp`) because it is where the entry lives; the
  server implementation itself is not in a public repository. The field is optional — drop it if
  pointing at metadata rather than source feels wrong.
- `icons` is omitted: the registry accepts only HTTPS PNG/JPEG/SVG/WebP and there is no
  brand-pack URL yet.
- **Human step:** the login (DNS TXT record or GitHub org-owner device flow) and the `publish`
  itself. The loop holds none of those credentials and publishes nothing.
