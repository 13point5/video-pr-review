### Browserbase

[Browserbase](https://browserbase.com) provides remote browser infrastructure to make deployment of agentic browsing agents easy. Use it when running the agent-browser CLI in an environment where a local browser isn't feasible.

To enable Browserbase, use the `-p` flag:

```bash
export BROWSERBASE_API_KEY="your-api-key"
export BROWSERBASE_PROJECT_ID="your-project-id"
agent-browser -p browserbase open https://example.com
```

Or use environment variables for CI/scripts:

```bash
export AGENT_BROWSER_PROVIDER=browserbase
export BROWSERBASE_API_KEY="your-api-key"
export BROWSERBASE_PROJECT_ID="your-project-id"
agent-browser open https://example.com
```

When enabled, agent-browser connects to a Browserbase session instead of launching a local browser. All commands work identically.

Get your API key and project ID from the [Browserbase Dashboard](https://browserbase.com/overview).

### Browser Use

[Browser Use](https://browser-use.com) provides cloud browser infrastructure for AI agents. Use it when running agent-browser in environments where a local browser isn't available (serverless, CI/CD, etc.).

To enable Browser Use, use the `-p` flag:

```bash
export BROWSER_USE_API_KEY="your-api-key"
agent-browser -p browseruse open https://example.com
```

Or use environment variables for CI/scripts:

```bash
export AGENT_BROWSER_PROVIDER=browseruse
export BROWSER_USE_API_KEY="your-api-key"
agent-browser open https://example.com
```

When enabled, agent-browser connects to a Browser Use cloud session instead of launching a local browser. All commands work identically.

Get your API key from the [Browser Use Cloud Dashboard](https://cloud.browser-use.com/settings?tab=api-keys). Free credits are available to get started, with pay-as-you-go pricing after.

### Kernel

[Kernel](https://www.kernel.sh) provides cloud browser infrastructure for AI agents with features like stealth mode and persistent profiles.

To enable Kernel, use the `-p` flag:

```bash
export KERNEL_API_KEY="your-api-key"
agent-browser -p kernel open https://example.com
```

Or use environment variables for CI/scripts:

```bash
export AGENT_BROWSER_PROVIDER=kernel
export KERNEL_API_KEY="your-api-key"
agent-browser open https://example.com
```

Optional configuration via environment variables:

| Variable                 | Description                                                                      | Default |
| ------------------------ | -------------------------------------------------------------------------------- | ------- |
| `KERNEL_HEADLESS`        | Run browser in headless mode (`true`/`false`)                                    | `false` |
| `KERNEL_STEALTH`         | Enable stealth mode to avoid bot detection (`true`/`false`)                      | `true`  |
| `KERNEL_TIMEOUT_SECONDS` | Session timeout in seconds                                                       | `300`   |
| `KERNEL_PROFILE_NAME`    | Browser profile name for persistent cookies/logins (created if it doesn't exist) | (none)  |

When enabled, agent-browser connects to a Kernel cloud session instead of launching a local browser. All commands work identically.

**Profile Persistence:** When `KERNEL_PROFILE_NAME` is set, the profile will be created if it doesn't already exist. Cookies, logins, and session data are automatically saved back to the profile when the browser session ends, making them available for future sessions.

Get your API key from the [Kernel Dashboard](https://dashboard.onkernel.com).
