/**
 * Colorful status: project, model/effort, and context first;
 * token usage and environment second; Codex weekly usage third.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { Buffer } from "node:buffer";
import { existsSync } from "node:fs";
import { basename, join } from "node:path";

type GitStatus = {
    repo: boolean;
    branch?: string;
    staged: number;
    unstaged: number;
    conflicts: number;
    untracked: number;
    ahead: number;
    behind: number;
};

const NO_GIT: GitStatus = {
    repo: false,
    staged: 0,
    unstaged: 0,
    conflicts: 0,
    untracked: 0,
    ahead: 0,
    behind: 0,
};

const CODEX_PROVIDER = "openai-codex";
const CODEX_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage";
const CODEX_WEEK_SECONDS = 7 * 24 * 60 * 60;
const CODEX_FETCH_TTL_MS = 5 * 60 * 1000;
const CODEX_DISPLAY_REFRESH_MS = 60 * 1000;
const CODEX_REQUEST_TIMEOUT_MS = 15 * 1000;

type CodexWeeklyUsage = {
    usedPercent: number;
    resetAt?: number;
};

async function getGitStatus(pi: ExtensionAPI, cwd: string): Promise<GitStatus> {
    const empty = { ...NO_GIT };
    const inside = await pi.exec(
        "git",
        ["rev-parse", "--is-inside-work-tree"],
        { cwd },
    );
    if (inside.code !== 0 || inside.stdout.trim() !== "true") return empty;

    const branchResult = await pi.exec(
        "git",
        ["branch", "--show-current"],
        { cwd },
    );
    let branch = branchResult.stdout.trim();
    if (!branch) {
        const detached = await pi.exec(
            "git",
            ["rev-parse", "--short", "HEAD"],
            { cwd },
        );
        branch = detached.stdout.trim() || "detached";
    }

    const statusResult = await pi.exec(
        "git",
        ["status", "--porcelain=v1"],
        { cwd },
    );
    let staged = 0;
    let unstaged = 0;
    let conflicts = 0;
    let untracked = 0;

    if (statusResult.code === 0) {
        for (const line of statusResult.stdout.split("\n")) {
            if (line.length < 3) continue;
            const x = line[0];
            const y = line[1];

            if (x === "?" && y === "?") {
                untracked++;
                continue;
            }
            if (
                x === "U" ||
                y === "U" ||
                (x === "A" && y === "A") ||
                (x === "D" && y === "D")
            ) {
                conflicts++;
                continue;
            }
            if (x !== " ") staged++;
            if (y !== " ") unstaged++;
        }
    }

    let ahead = 0;
    let behind = 0;
    const tracking = await pi.exec(
        "git",
        ["rev-list", "--left-right", "--count", "@{upstream}...HEAD"],
        { cwd },
    );
    if (tracking.code === 0) {
        const [behindText, aheadText] = tracking.stdout.trim().split(/\s+/);
        behind = Number.parseInt(behindText ?? "0", 10) || 0;
        ahead = Number.parseInt(aheadText ?? "0", 10) || 0;
    }

    return {
        repo: true,
        branch,
        staged,
        unstaged,
        conflicts,
        untracked,
        ahead,
        behind,
    };
}

function formatTokens(count: number): string {
    if (count < 1000) return String(count);
    if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
    if (count < 1_000_000) return `${Math.round(count / 1000)}k`;
    return `${(count / 1_000_000).toFixed(1)}M`;
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
    if (!value || typeof value !== "object" || Array.isArray(value)) return undefined;
    return value as Record<string, unknown>;
}

function asNumber(value: unknown): number | undefined {
    if (typeof value === "number" && Number.isFinite(value)) return value;
    if (typeof value === "string" && value.trim()) {
        const parsed = Number(value);
        if (Number.isFinite(parsed)) return parsed;
    }
    return undefined;
}

function parseCodexWeeklyUsage(
    payload: unknown,
    capturedAt = Date.now(),
): CodexWeeklyUsage {
    const rateLimit = asRecord(asRecord(payload)?.rate_limit);
    if (!rateLimit) throw new Error("Codex usage response had no rate limit.");

    const windows = [rateLimit.primary_window, rateLimit.secondary_window]
        .map(asRecord)
        .filter((window): window is Record<string, unknown> => Boolean(window));
    const weekly = windows.find((window) => {
        const seconds = asNumber(window.limit_window_seconds);
        return seconds !== undefined && Math.abs(seconds - CODEX_WEEK_SECONDS) <= 60;
    });
    if (!weekly) throw new Error("Codex usage response had no weekly window.");

    const usedPercent = asNumber(weekly.used_percent);
    if (usedPercent === undefined) {
        throw new Error("Codex weekly usage percentage was unavailable.");
    }

    const rawResetAt = asNumber(weekly.reset_at);
    const resetAfterSeconds = asNumber(weekly.reset_after_seconds);
    const resetAt = rawResetAt !== undefined && rawResetAt > 0
        ? rawResetAt < 10_000_000_000
            ? rawResetAt * 1000
            : rawResetAt
        : resetAfterSeconds !== undefined && resetAfterSeconds >= 0
          ? capturedAt + resetAfterSeconds * 1000
          : undefined;

    return {
        usedPercent: Math.min(100, Math.max(0, usedPercent)),
        resetAt,
    };
}

function codexAccountId(token: string): string | undefined {
    try {
        const encodedPayload = token.split(".")[1];
        if (!encodedPayload) return undefined;
        const payload = JSON.parse(
            Buffer.from(encodedPayload, "base64url").toString("utf8"),
        ) as Record<string, unknown>;
        const auth = asRecord(payload["https://api.openai.com/auth"]);
        return typeof auth?.chatgpt_account_id === "string"
            ? auth.chatgpt_account_id
            : undefined;
    } catch {
        return undefined;
    }
}

async function fetchCodexWeeklyUsage(
    ctx: ExtensionContext,
    signal: AbortSignal,
): Promise<CodexWeeklyUsage> {
    const resolved = await ctx.modelRegistry.getProviderAuth(CODEX_PROVIDER);
    const auth = resolved?.auth;
    const headers = new Headers({ Accept: "application/json" });
    for (const [name, value] of Object.entries(auth?.headers ?? {})) {
        if (value !== null) headers.set(name, value);
    }
    if (!headers.has("Authorization") && auth?.apiKey) {
        headers.set("Authorization", `Bearer ${auth.apiKey}`);
    }

    const authorization = headers.get("Authorization");
    if (!authorization) throw new Error("Codex subscription auth is unavailable.");
    if (!headers.has("chatgpt-account-id")) {
        const accountId = codexAccountId(authorization.replace(/^Bearer\s+/i, ""));
        if (accountId) headers.set("chatgpt-account-id", accountId);
    }
    headers.set("originator", "pi");

    const response = await fetch(CODEX_USAGE_URL, { headers, signal });
    if (!response.ok) throw new Error(`Codex usage request failed (${response.status}).`);
    return parseCodexWeeklyUsage(await response.json());
}

function resetCountdown(resetAt: number | undefined, now = Date.now()): string {
    if (resetAt === undefined) return "unknown";
    const remainingMs = Math.max(0, resetAt - now);
    if (remainingMs === 0) return "now";

    const minutes = Math.ceil(remainingMs / 60_000);
    if (minutes < 60) return `${minutes}m`;

    const hours = remainingMs / 3_600_000;
    if (hours < 48) return `${Math.ceil(hours * 10) / 10}h`;

    const days = remainingMs / 86_400_000;
    return `${Math.ceil(days * 10) / 10}d`;
}

function codexUsageLine(usage: CodexWeeklyUsage, theme: any): string {
    const percent = Number.isInteger(usage.usedPercent)
        ? usage.usedPercent.toFixed(0)
        : usage.usedPercent.toFixed(1);
    const tone = usage.usedPercent >= 80
        ? "error"
        : usage.usedPercent >= 60
          ? "warning"
          : "success";
    return (
        theme.fg("accent", theme.bold("Codex")) +
        theme.fg("dim", " · weekly ") +
        theme.fg(tone, theme.bold(`${percent}% used`)) +
        theme.fg("dim", ` · resets in ${resetCountdown(usage.resetAt)}`)
    );
}

function formatCwd(cwd: string): string {
    const home = process.env.HOME;
    if (!home) return cwd;
    if (cwd === home) return "~";
    if (cwd.startsWith(`${home}/`)) return `~/${cwd.slice(home.length + 1)}`;
    return cwd;
}

function statusLabel(status: GitStatus, theme: any): string {
    if (!status.repo) return theme.fg("muted", "no git");

    // Keep git status ASCII-only for compatibility with every terminal/font.
    const parts: string[] = [];
    if (status.conflicts) parts.push(theme.fg("error", `C${status.conflicts}`));
    if (status.staged) parts.push(theme.fg("success", `S${status.staged}`));
    if (status.unstaged) parts.push(theme.fg("warning", `M${status.unstaged}`));
    if (status.untracked) parts.push(theme.fg("muted", `U${status.untracked}`));
    if (status.ahead) parts.push(theme.fg("success", `A${status.ahead}`));
    if (status.behind) parts.push(theme.fg("warning", `B${status.behind}`));

    return parts.length > 0 ? parts.join(" ") : theme.fg("success", "OK");
}

function thinkingColor(level: string): string {
    const colors: Record<string, string> = {
        off: "thinkingOff",
        minimal: "thinkingMinimal",
        low: "thinkingLow",
        medium: "thinkingMedium",
        high: "thinkingHigh",
        xhigh: "thinkingXhigh",
        max: "thinkingMax",
    };
    return colors[level] ?? "accent";
}

function modelAndContext(
    pi: ExtensionAPI,
    ctx: ExtensionContext,
    theme: any,
): [model: string, context: string] {
    const effort = pi.getThinkingLevel();
    const model =
        theme.fg("accent", theme.bold(ctx.model?.id ?? "no model")) +
        theme.fg("dim", " · ") +
        theme.fg(thinkingColor(effort), theme.bold(effort));

    const usage = ctx.getContextUsage();
    let context: string;
    if (!usage || usage.contextWindow <= 0) {
        context = theme.fg("warning", theme.bold("unknown"));
    } else if (usage.tokens === null) {
        context = theme.fg(
            "warning",
            theme.bold(`? / ${formatTokens(usage.contextWindow)}`),
        );
    } else {
        const percent = Math.max(
            0,
            Math.min(100, (usage.tokens / usage.contextWindow) * 100),
        );
        const color = percent >= 90 ? "error" : percent >= 70 ? "warning" : "success";
        const barWidth = 8;
        const filled = Math.round((percent / 100) * barWidth);
        const bar =
            theme.fg(color, "█".repeat(filled)) +
            theme.fg("dim", "░".repeat(barWidth - filled));
        context =
            bar +
            " " +
            theme.fg(color, theme.bold(`${percent.toFixed(1)}%`)) +
            theme.fg(
                "dim",
                ` ${formatTokens(usage.tokens)} / ${formatTokens(usage.contextWindow)}`,
            );
    }

    return [model, context];
}

function sanitize(text: string): string {
    return text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
}

function detectProjectEnvironment(cwd: string): string {
    const virtualEnv = process.env.VIRTUAL_ENV;
    if (virtualEnv) return `venv:${basename(virtualEnv)}`;

    const condaEnv = process.env.CONDA_DEFAULT_ENV;
    if (condaEnv) return `conda:${condaEnv}`;

    const markers: Array<[string, string]> = [
        ["bun.lockb", "bun"],
        ["bun.lock", "bun"],
        ["pnpm-lock.yaml", "pnpm"],
        ["yarn.lock", "yarn"],
        ["package-lock.json", "npm"],
        ["uv.lock", "uv"],
        ["pyproject.toml", "python"],
        ["Cargo.toml", "rust"],
        ["go.mod", "go"],
        ["hugo.toml", "hugo"],
        ["config.toml", "hugo"],
    ];

    const found = markers
        .filter(([marker]) => existsSync(join(cwd, marker)))
        .map(([, name]) => name);
    return [...new Set(found)].join("+") || process.env.NODE_ENV || "system";
}

function sessionStats(ctx: ExtensionContext): {
    input: number;
    output: number;
    cacheRead: number;
    cacheWrite: number;
    cacheHitRate?: number;
    cost: number;
} {
    let input = 0;
    let output = 0;
    let cacheRead = 0;
    let cacheWrite = 0;
    let cacheHitRate: number | undefined;
    let cost = 0;

    for (const entry of ctx.sessionManager.getEntries()) {
        if (entry.type !== "message" || entry.message.role !== "assistant") continue;
        const usage = entry.message.usage;
        input += usage.input;
        output += usage.output;
        cacheRead += usage.cacheRead;
        cacheWrite += usage.cacheWrite;
        cost += usage.cost.total;

        const latestPromptTokens = usage.input + usage.cacheRead + usage.cacheWrite;
        cacheHitRate = latestPromptTokens > 0
            ? (usage.cacheRead / latestPromptTokens) * 100
            : undefined;
    }

    return { input, output, cacheRead, cacheWrite, cacheHitRate, cost };
}

export default function (pi: ExtensionAPI) {
    let current: GitStatus = { ...NO_GIT };
    let fetching = false;
    let requestRender: (() => void) | undefined;
    let projectEnvironment = "system";
    let activeContext: ExtensionContext | undefined;
    let codexUsage: CodexWeeklyUsage | undefined;
    let codexUsageFetchedAt = 0;
    let codexUsageLoading = false;
    let codexUsageFailed = false;
    let codexRequest: AbortController | undefined;
    let codexRefreshTimer: ReturnType<typeof setInterval> | undefined;
    let enabled = false;

    function stopSessionResources(): void {
        enabled = false;
        if (codexRefreshTimer) clearInterval(codexRefreshTimer);
        codexRefreshTimer = undefined;
        codexRequest?.abort();
        codexRequest = undefined;
        activeContext = undefined;
        requestRender = undefined;
    }

    async function refresh(ctx: ExtensionContext): Promise<void> {
        if (fetching) return;
        fetching = true;
        try {
            current = await getGitStatus(pi, ctx.cwd);
            requestRender?.();
        } finally {
            fetching = false;
        }
    }

    async function refreshCodexUsage(
        ctx: ExtensionContext,
        force = false,
    ): Promise<void> {
        if (ctx.model?.provider !== CODEX_PROVIDER) return;
        if (
            !force &&
            codexUsage &&
            Date.now() - codexUsageFetchedAt < CODEX_FETCH_TTL_MS
        ) {
            requestRender?.();
            return;
        }
        if (codexUsageLoading && !force) return;

        codexRequest?.abort();
        const controller = new AbortController();
        codexRequest = controller;
        codexUsageLoading = true;
        codexUsageFailed = false;
        requestRender?.();
        const timeout = setTimeout(() => controller.abort(), CODEX_REQUEST_TIMEOUT_MS);

        try {
            const usage = await fetchCodexWeeklyUsage(ctx, controller.signal);
            if (activeContext !== ctx || ctx.model?.provider !== CODEX_PROVIDER) return;
            codexUsage = usage;
            codexUsageFetchedAt = Date.now();
        } catch (error) {
            if (!(error instanceof Error && error.name === "AbortError") && !codexUsage) {
                codexUsageFailed = true;
            }
        } finally {
            clearTimeout(timeout);
            if (codexRequest === controller) {
                codexRequest = undefined;
                codexUsageLoading = false;
            }
            requestRender?.();
        }
    }

    pi.on("session_start", async (_event, ctx) => {
        // SDK-created subagent sessions default to print mode and still load global
        // extensions. Do not create UI resources there: AgentSession.dispose()
        // invalidates the context without emitting session_shutdown.
        if (ctx.mode !== "tui") return;

        enabled = true;
        activeContext = ctx;
        projectEnvironment = detectProjectEnvironment(ctx.cwd);
        if (ctx.mode === "tui") {
            ctx.ui.setFooter((tui, theme, footerData) => {
                const unsubscribe = footerData.onBranchChange(() => {
                    tui.requestRender();
                    void refresh(ctx);
                });
                requestRender = () => tui.requestRender();

                return {
                    dispose: () => {
                        unsubscribe();
                        requestRender = undefined;
                    },
                    invalidate() {},
                    render(width: number): string[] {
                        const divider = theme.fg("dim", "  │  ");
                        const branchName = footerData.getGitBranch();
                        const project = branchName
                            ? theme.fg("text", theme.bold(formatCwd(ctx.cwd))) +
                              theme.fg("dim", " · ") +
                              theme.fg("accent", branchName) +
                              " " +
                              statusLabel({ ...current, repo: true }, theme)
                            : theme.fg("text", theme.bold(formatCwd(ctx.cwd))) +
                              theme.fg("dim", " · ") +
                              statusLabel({ ...current, repo: false }, theme);
                        const [model, context] = modelAndContext(pi, ctx, theme);
                        const fixedWidth =
                            visibleWidth(model) +
                            visibleWidth(context) +
                            visibleWidth(divider) * 2;
                        const projectWidth = Math.max(1, width - fixedWidth);
                        const primary = truncateToWidth(project, projectWidth, "");
                        const firstLine = truncateToWidth(
                            [primary, model, context].join(divider),
                            width,
                            "",
                        );

                        const stats = sessionStats(ctx);
                        const tokenParts: string[] = [
                            theme.fg("accent", `↑${formatTokens(stats.input)}`),
                            theme.fg("success", `↓${formatTokens(stats.output)}`),
                        ];
                        if (stats.cacheRead) {
                            tokenParts.push(
                                theme.fg("warning", `R${formatTokens(stats.cacheRead)}`),
                            );
                        }
                        if (
                            (stats.cacheRead || stats.cacheWrite) &&
                            stats.cacheHitRate !== undefined
                        ) {
                            tokenParts.push(
                                theme.fg("muted", `CH ${stats.cacheHitRate.toFixed(1)}%`),
                            );
                        }
                        tokenParts.push(
                            theme.fg("customMessageLabel", `$${stats.cost.toFixed(3)}`),
                        );

                        const secondLine = truncateToWidth(
                            tokenParts.join(" ") +
                                divider +
                                theme.fg("dim", `env ${projectEnvironment}`),
                            width,
                            "",
                        );
                        const statuses = [...footerData.getExtensionStatuses().values()]
                            .map(sanitize)
                            .filter(Boolean);

                        const lines = [firstLine, secondLine];
                        if (ctx.model?.provider === CODEX_PROVIDER) {
                            const codexLine = codexUsage
                                ? codexUsageLine(codexUsage, theme)
                                : theme.fg(
                                      codexUsageFailed ? "warning" : "dim",
                                      codexUsageFailed
                                          ? "Codex weekly usage unavailable"
                                          : "Codex weekly usage…",
                                  );
                            lines.push(truncateToWidth(codexLine, width, ""));
                        }

                        return [
                            ...lines,
                            ...statuses.map((s) => truncateToWidth(s, width, "")),
                        ];
                    },
                };
            });
        }
        codexRefreshTimer = setInterval(() => {
            const ctx = activeContext;
            if (!enabled || !ctx) return;

            try {
                if (ctx.model?.provider !== CODEX_PROVIDER) return;
            } catch {
                // Some SDK consumers dispose sessions without session_shutdown.
                // Treat a stale context as implicit teardown instead of crashing pi.
                stopSessionResources();
                return;
            }

            requestRender?.();
            void refreshCodexUsage(ctx);
        }, CODEX_DISPLAY_REFRESH_MS);
        codexRefreshTimer.unref?.();

        void refreshCodexUsage(ctx);
        await refresh(ctx);
    });

    pi.on("tool_result", async (event, ctx) => {
        if (enabled && ["bash", "edit", "write"].includes(event.toolName)) {
            await refresh(ctx);
        }
    });

    pi.on("turn_end", async (_event, ctx) => {
        if (!enabled) return;
        await refresh(ctx);
        void refreshCodexUsage(ctx);
        requestRender?.();
    });

    pi.on("thinking_level_select", () => {
        if (enabled) requestRender?.();
    });

    pi.on("model_select", (_event, ctx) => {
        if (!enabled) return;
        if (ctx.model?.provider === CODEX_PROVIDER) {
            void refreshCodexUsage(ctx);
        } else {
            codexRequest?.abort();
        }
        requestRender?.();
    });

    pi.on("after_provider_response", (event, ctx) => {
        if (enabled && event.status === 429 && ctx.model?.provider === CODEX_PROVIDER) {
            void refreshCodexUsage(ctx, true);
        }
    });

    pi.on("session_compact", () => {
        if (enabled) requestRender?.();
    });

    pi.on("session_shutdown", () => {
        stopSessionResources();
    });
}
