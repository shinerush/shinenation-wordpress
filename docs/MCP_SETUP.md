# Connecting this project to shinenationtech.com over MCP

Target site: **https://shinenationtech.com** (WordPress, hosted on Hostinger).

Nothing in this guide modifies the website. Every step is either local
configuration or a read-only request.

---

## 1. Two servers, two different jobs

`Hostinger MCP` and `WordPress MCP` are not alternatives — they operate at
different layers, and they authenticate with different credentials.

| | **WordPress MCP** | **Hostinger MCP** |
|---|---|---|
| Reaches | WordPress itself, via `/wp-json/` | The hosting account, via Hostinger's API |
| Credential | **Application Password** (the one you created) | Hostinger API token, or OAuth sign-in |
| Good for | Posts, pages, media, users, comments, categories, taxonomies, SEO fields | DNS records, SSL, backups, cache purging, plugin/theme deployment, staging, WordPress core version |
| Cannot do | Touch DNS, backups, or server config | Edit a post's content |

The Application Password you already generated is **only** used by the
WordPress server. It has no meaning to Hostinger's API.

Recommendation: set up **WordPress MCP first**. It is what you need for
day-to-day site management, and it uses the credential you already have.
Add Hostinger MCP only when you actually need DNS, backups, or cache control.

---

## 2. Where to run this — read this before anything else

This repository is currently checked out in a **Claude Code cloud sandbox**,
and that sandbox's network policy **blocks outbound traffic to
`shinenationtech.com`** (verified: the egress proxy answers `403` to
`CONNECT shinenationtech.com:443`). It also blocks `hostinger.com`.

Consequences:

- An MCP server started **inside the cloud sandbox cannot reach your site.**
  Configuring it here will fail at the first request, no matter how correct
  the credentials are.
- Run the MCP servers on your **local machine** — Claude Code CLI or Claude
  Desktop — where your own network reaches the site normally.

If you specifically want the cloud sandbox to reach the site, the domain has
to be added to the environment's network allowlist in the Claude Code web
environment settings; see
<https://code.claude.com/docs/en/claude-code-on-the-web>.

---

## 3. Prerequisites

- **Node.js 18+** for the WordPress server (`node --version`).
  Hostinger's server requires **Node 24+**, so check this if you add it later.
- Your WordPress **username** — the account that owns the Application
  Password. This is the login username, *not* the label you typed when
  creating the password, and not the site name.
- The **Application Password** itself, in its `xxxx xxxx xxxx xxxx xxxx xxxx`
  form. Keep the spaces; WordPress strips them server-side either way.

If you no longer have the password value — it is shown exactly once — revoke
that entry in **Users → Profile → Application Passwords** and create a new
one. Do not reuse your login password.

---

## 4. Store the credentials (locally, never committed)

```bash
git clone https://github.com/shinerush/shinenation-wordpress.git
cd shinenation-wordpress

cp .env.example .env
# edit .env with your real values
chmod 600 .env
```

`.env` is listed in `.gitignore`, together with `credentials.json`, `*.key`,
and `.claude/settings.local.json`. Confirm before your first commit:

```bash
git check-ignore -v .env      # must print a .gitignore match
git status --short            # .env must NOT appear
```

**Never** paste the Application Password into `.mcp.json`, a commit message,
an issue, or a chat message. `.mcp.json` in this repo deliberately contains
only `${VAR}` placeholders.

---

## 5. Verify the connection before wiring up MCP

Run the read-only preflight. It issues `GET` requests only — no writes:

```bash
set -a; source .env; set +a
./scripts/verify-wp-connection.sh
```

It checks, in order:

1. the variables are set and the URL is `https`,
2. `GET /wp-json/` returns 200 and advertises the `wp/v2` namespace,
3. `GET /wp-json/wp/v2/users/me` authenticates with your Application
   Password, and reports the resolved user and roles,
4. posts are readable in `edit` context.

Get this green first. Debugging a 401 here takes seconds; debugging it
through an MCP handshake does not.

### If step 2 fails (REST API unreachable)

A security plugin (Wordfence, iThemes), a Cloudflare rule, or Hostinger's
firewall is blocking `/wp-json/`. Allowlist the REST API rather than
disabling the plugin.

### If step 3 returns 401

In order of likelihood:

1. Wrong `WORDPRESS_USERNAME` — use the login username, not the password label.
2. The password was mistyped, or was revoked in WP Admin.
3. The `Authorization` header is being stripped before it reaches PHP. This
   happens on some Apache/LiteSpeed configurations. Fix by adding to
   `.htaccess`:

   ```apache
   SetEnvIf Authorization "(.*)" HTTP_AUTHORIZATION=$1
   ```

   This is a change to the *site*, so make it deliberately — it is not part
   of this setup unless step 3 forces it.

---

## 6. Connect the WordPress MCP server

The repo ships a project-scoped `.mcp.json` that reads credentials from your
environment, so no secret ever lands in a tracked file. Launch Claude Code
with the variables loaded:

```bash
set -a; source .env; set +a
claude
```

Claude Code will prompt once to approve the project-scoped servers in
`.mcp.json`. Approve `wordpress`.

Verify inside Claude Code:

```
/mcp
```

`wordpress` should show as **connected**. Then ask, in chat:

> Test my WordPress connection and list the 5 most recent posts.

**Alternative — user-scoped, without this repo's `.mcp.json`:**

```bash
claude mcp add --scope user \
  --env WORDPRESS_SITE_URL=https://shinenationtech.com \
  --env WORDPRESS_USERNAME=your-wp-username \
  --env "WORDPRESS_APP_PASSWORD=xxxx xxxx xxxx xxxx xxxx xxxx" \
  --transport stdio wordpress \
  -- npx -y mcp-wordpress
```

Note this writes the password in plaintext into `~/.claude.json` and into
your shell history. The `.env` approach above is preferable.

**Claude Desktop:** install the `.dxt` extension from the
[mcp-wordpress releases page](https://github.com/docdyhr/mcp-wordpress/releases/latest)
and enter the same three values in its settings pane.

---

## 7. Optionally add Hostinger MCP

Only needed for hosting-level control (DNS, backups, cache, SSL, deploying a
plugin or theme file). Hostinger publishes a hosted server with OAuth, which
avoids handling a token entirely:

```bash
claude mcp add --scope user --transport http hostinger https://mcp.hostinger.com
```

A browser window opens for sign-in. Approve only the account that owns
shinenationtech.com.

Running it locally instead (requires Node 24+):

```bash
npm install -g @hostinger/mcp
```

The package installs scope-limited binaries. Prefer a narrow one over the
386-tool `hostinger-api-mcp` default:

| Binary | Tools | Scope |
|---|---|---|
| `hostinger-hosting-mcp` | 64 | hosting, cache, plugin/theme deploy |
| `hostinger-dns-mcp` | 8 | DNS records only |
| `hostinger-domains-mcp` | 40 | domains |
| `hostinger-wordpress-mcp` | 38 | WordPress-specific hosting operations |
| `hostinger-api-mcp` | 386 | everything (includes billing and VPS) |

Set `HOSTINGER_API_TOKEN` (hPanel → Account → API) to skip OAuth. Add it to
`.env`, never to `.mcp.json`.

---

## 8. Safety posture

The Application Password inherits **every capability of its user account**.
There is no per-password scoping in WordPress core.

- Point the integration at a dedicated WordPress user with the narrowest role
  that still does the job — `Editor` covers content work. Reserve
  `Administrator` for when you genuinely need plugin or settings control.
- Revoking is immediate and self-contained: delete that entry under
  **Users → Profile → Application Passwords**. Do this the moment a password
  is exposed, and rotate on a schedule.
- Prefer the narrowest Hostinger binary; the full server exposes billing,
  payments, and VPS destruction alongside the hosting tools.
- Take a backup before the first write operation. Hostinger MCP can trigger
  one, or use hPanel directly.
- Ask for a dry run before destructive requests — "show me what you would
  change" — since MCP writes to a live production site take effect
  immediately.

---

## 9. Checklist

- [ ] Running on a machine that can reach shinenationtech.com (not the cloud sandbox)
- [ ] `.env` created, `chmod 600`, confirmed ignored by git
- [ ] `./scripts/verify-wp-connection.sh` passes all critical checks
- [ ] `/mcp` shows `wordpress` connected
- [ ] Role of the integration user reviewed and reduced where possible
- [ ] Backup taken before the first write
- [ ] (Optional) Hostinger MCP added, narrowest useful scope
