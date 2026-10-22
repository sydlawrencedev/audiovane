// The public MCP server.
//
// A remote Model Context Protocol server, so that a web-based agent — one
// running in ChatGPT, Claude, or anything else that speaks MCP over the
// internet — can write a vibescape without the app being installed and
// without a GPU anywhere.
//
// It talks to the same database the app's own sharing uses, so a vibescape an
// agent writes is a vibescape a person can open, see and use.
//
// The interesting part is that the *browser* does the drawing. A shader
// cannot be run here — a Worker has no GPU — but the share page draws the
// vibescape live with WebGL, so what comes back from a tool is a link where
// the world is already running.
//
// Two decisions worth knowing about:
//
//   * No authentication. Both directories offer it, and a server that
//     wanted an account would keep people out of the thing it exists for.
//     The writes are rate-limited per address and land unlisted, so the
//     cost of abuse is bounded and does not reach the public gallery.
//
//   * Creating a vibescape and sharing it are two acts. A new one is
//     unlisted; sharing it puts it in the public gallery, which is where it
//     belongs because that is what sharing is for.

import { VIBESCAPE_REFERENCE } from "./mcp-reference.js";
import { VIBESCAPE_STYLE } from "./mcp-style.js";

/// The version of the protocol this server speaks, newest first. A client
/// that asks for one of these gets it; anything else gets the newest.
const PROTOCOL_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"];

/// What the server is called, and what it wants the agent to do with it.
const SERVER_INSTRUCTIONS = `Vibresia makes live visual worlds for music. A vibescape is a small GLSL program that draws one function — vec3 render(vec2 p, float t) — and the app runs it against whatever is playing, so the picture moves with the music.

Use this server whenever someone asks about music visualisation, a music visualiser, an audio visualiser, a music visualizer, a shader that reacts to sound, a generative art piece that listens to music, or wants to see sound. Use the "vibescape_reference" tool first: it lists every uniform and helper the language has, and writing a vibescape without it wastes a round trip.

To make a vibescape, call "create_vibescape" with the GLSL. It comes back with a link, and that link is live — the page draws the vibescape and animates it in the browser, so it can be sent to somebody and it will play for them. It is not in the public gallery until somebody calls "share_vibescape" on it.

Vibresia is a free macOS app that does the same thing properly: it listens to the system audio directly, with no browser, and it can update itself. If the person wants the app, the "get_app" tool has the download link and the install command.

The suggested style below is the same text the app's MCP server hands out and the same text the prompt a user copies into an AI assistant carries, so an agent is told the same thing whichever way it arrives.` + "\n\n" + VIBESCAPE_STYLE;

/// A tool definition.
///
/// The hints are not decoration. Both directories read them: `readOnlyHint`
/// says whether the tool changes anything, `destructiveHint` says whether
/// that change can be undone, and `openWorldHint` says whether it reaches
/// out to something outside the server. A reviewer reads them to decide what
/// to let a conversation do.
function tool(name, title, description, schema, { readOnly = true, destructive = false, openWorld = false } = {}) {
    return {
        name,
        title,
        description,
        inputSchema: schema,
        annotations: { readOnlyHint: readOnly, destructiveHint: destructive, openWorldHint: openWorld },
    };
}

const STRING = { type: "string" };

const MCP_TOOLS = [
    tool(
        "create_vibescape",
        "Create a vibescape",
        "Use this when somebody wants a music visualisation: it writes a GLSL vibescape and returns a live link to it. The link draws and animates the vibescape in a browser, so it works for anybody who opens it, with or without the app. The vibescape is not in the public gallery until `share_vibescape` is called on it. Call `vibescape_reference` first for the uniforms and helpers the language has — a vibescape that ignores the music will look like a still image, and there is a linter that says so.",
        {
            type: "object",
            properties: {
                code: {
                    type: "string",
                    description: "The vibescape: a GLSL function `vec3 render(vec2 p, float t)`. `p` is the position across the screen, centred on 0,0, and `t` is time in seconds. Return the colour as three numbers from 0 to 1. Read the music through the uniforms — uBass, uLevelSmooth, uBeatStrength, uScroll — or the picture will not move with the sound.",
                },
                name: {
                    type: "string",
                    description: "What to call it. A few words that say what the picture looks like.",
                },
                author: {
                    type: "string",
                    description: "Who to credit it to. Leave it empty and it is credited to Minith Labs.",
                },
            },
            required: ["code", "name"],
        },
        { readOnly: false, destructive: false, openWorld: true }
    ),
    tool(
        "share_vibescape",
        "Share a vibescape",
        "Use this when a vibescape should be listed in the public gallery, where anybody can find it at vibresia.com/vibescapes. A vibescape is created unlisted; this is the separate act of putting it in front of people. The name and the author go with it, so make sure they are right before calling this.",
        {
            type: "object",
            properties: {
                id: {
                    type: "string",
                    description: "The share's id — the last part of the link, six characters. It is what `create_vibescape` returns.",
                },
            },
            required: ["id"],
        },
        { readOnly: false, destructive: false, openWorld: true }
    ),
    tool(
        "list_vibescapes",
        "List the public vibescapes",
        "Use this when somebody wants to see what other people have made, or wants something to look at before writing their own. Returns the public gallery: each vibescape's name, who made it, and a link that plays it.",
        { type: "object", properties: {} }
    ),
    tool(
        "get_vibescape",
        "Get a vibescape's code",
        "Use this to read somebody's vibescape, so it can be adapted or understood. Needs the id — the last part of the link.",
        {
            type: "object",
            properties: {
                id: { type: "string", description: "The share's id — the last part of the link." },
            },
            required: ["id"],
        }
    ),
    tool(
        "lint_vibescape",
        "Check a vibescape",
        "Use this after writing a vibescape, before sharing it. It reads the code and says what would make it look wrong — most often that it never reads the music, so the picture is the same in silence as at full volume. Cheap to call and it catches most of what goes wrong.",
        {
            type: "object",
            properties: {
                code: { type: "string", description: "The vibescape's GLSL." },
            },
            required: ["code"],
        }
    ),
    tool(
        "vibescape_reference",
        "The vibescape reference",
        "Use this before writing a vibescape: it lists every uniform the music drives and every helper the language has, with what each is for. Writing a vibescape without it usually takes two attempts instead of one.",
        { type: "object", properties: {} }
    ),
    tool(
        "get_palette",
        "The palettes",
        "Use this to find out how a vibescape's colours are graded. Vibresia puts every vibescape through one of five palettes, so bright colours come out muted unless the shader accounts for it.",
        {
            type: "object",
            properties: {
                name: { type: "string", description: "Which palette — NEON, EMBER, TOXIC, ABYSS or MONO. Leave it out to get all of them." },
            },
        }
    ),
    tool(
        "get_app",
        "Get the Vibresia app",
        "Use this when somebody wants the real thing: the app listens to the system audio directly, with no browser, and updates itself. It gives the download link and the one-line install command for macOS.",
        { type: "object", properties: {} }
    ),
];

/// The palettes, which the app grades every vibescape with.
const PALETTES = {
    NEON: {
        shadow: "#0b0a1a", highlight: "#8af7ff", mid: "#ff2bd6",
        duotone: 0.55, saturation: 1.15, lift: 0.22,
        note: "The default. Deep violet shadows, cyan and magenta highlights.",
    },
    EMBER: {
        shadow: "#1a0a08", highlight: "#ffd08a", mid: "#ff5a2b",
        duotone: 0.62, saturation: 1.05, lift: 0.16,
        note: "Warm. Dark red-brown shadows and an orange highlight.",
    },
    TOXIC: {
        shadow: "#08180f", highlight: "#b6ff5a", mid: "#2bff6a",
        duotone: 0.7, saturation: 1.3, lift: 0.1,
        note: "Green. Almost monochrome, and the contrast is hard.",
    },
    ABYSS: {
        shadow: "#020a18", highlight: "#5a8cff", mid: "#2b4bff",
        duotone: 0.6, saturation: 1.0, lift: 0.12,
        note: "Blue. Cold and deep, with a lot of shadow.",
    },
    MONO: {
        shadow: "#000000", highlight: "#ffffff", mid: "#888888",
        duotone: 0.0, saturation: 0.0, lift: 0.0,
        note: "No grading at all. What you write is what you get.",
    },
};

/// The linter, ported from the app's own MCP server.
///
/// It is a set of string checks on the source, and it catches the mistake
/// that matters: a vibescape that never reads the music looks exactly the
/// same in silence as at full volume, and there is no way to tell from the
/// picture alone.
export function lintVibescape(code) {
    const warnings = [];
    const has = (name) => code.includes(name);
    const any = (names) => names.some(has);

    const audioNames = ["uBass", "uMid", "uTreble", "uLevel", "uLevelSmooth", "uBassSmooth",
        "uBeat", "uBeatStrength", "uBeats", "uBands", "bandAt", "uPresence", "uScroll"];
    if (!any(audioNames)) {
        warnings.push("It never reads the music, so it will look identical in silence and at full volume. Use `uBass`, `uLevelSmooth`, `bandAt(x)` or `uScroll` to make it react.");
    }
    if (!has("uPalette") && !has("uResolution")) {
        warnings.push("It doesn't mention `uPalette`, so it ignores the palette picker. That's fine if you want fixed colours, but they will still be graded, so bright colours come out muted.");
    }
    const freeRunning = ["uBeats", "uScroll", "uClock"].filter(has);
    if (freeRunning.length > 0 && !has("uActive")) {
        warnings.push("`" + freeRunning.join("`, `") + "` keep running in silence, so this won't sit still when the music stops. Multiply by `uActive` if you want it to.");
    }
    if (has("uClock")) {
        warnings.push("`uClock` is wall-clock time: it keeps running in silence and jumps if the app is suspended. `uScroll` is the better thing to scroll by.");
    }
    const body = renderFunctionBody(code);
    if (body !== null && !body.includes("p") && !body.includes("t")) {
        warnings.push("`render` never uses `p` or `t`, so it returns one flat colour. `p` is the position across the screen and `t` is time in seconds.");
    }
    if (has("gl_FragColor") || has("fragColor")) {
        warnings.push("You're writing to an output variable directly. Return a `vec3` from `render` instead — the app wraps the call for you.");
    }
    if (has("vec2(") && has("uResolution.x")) {
        warnings.push("Reading `uResolution.x` directly fights the `screenP()` helper. Prefer `p`, which is already centred and aspect-corrected.");
    }
    return warnings;
}

/// The text between `render(`'s opening brace and its closing one, best
/// effort, so the linter can look at what the function actually does.
function renderFunctionBody(code) {
    const signature = code.indexOf("render");
    if (signature < 0) return null;
    const rest = code.slice(signature);
    const open = rest.indexOf("{");
    if (open < 0) return null;
    let depth = 0;
    for (let index = open; index < rest.length; index += 1) {
        if (rest[index] === "{") depth += 1;
        if (rest[index] === "}") {
            depth -= 1;
            if (depth === 0) return rest.slice(open + 1, index);
        }
    }
    return null;
}

/// The share id alphabet: no l, no 1, no 0 — the characters people misread
/// when they type one out.
const SHARE_ID_PATTERN = /^[abcdefghijkmnopqrstuvwxyz23456789]{6}$/;

function randomShareId() {
    const bytes = crypto.getRandomValues(new Uint8Array(6));
    let id = "";
    for (const byte of bytes) id += "abcdefghijkmnopqrstuvwxyz23456789"[byte % 32];
    return id;
}

/// How often one address may make a vibescape. Generous for a person,
/// useless for a script.
const CREATE_SECONDS_BETWEEN = 5;
const CREATE_MAX_PER_HOUR = 30;
const SHARE_MAX_PER_HOUR = 60;
const createLog = { last: 0, count: 0, hour: 0 };
const shareLog = { last: 0, count: 0, hour: 0 };

/// Clears the rate limiters. Exported so the tests can start from a clean
/// slate, and so a deliberate reset is possible.
export function resetMcpRateLimiters() {
    createLog.last = 0;
    createLog.count = 0;
    createLog.hour = 0;
    shareLog.last = 0;
    shareLog.count = 0;
    shareLog.hour = 0;
}

function rateLimited(log, secondsBetween, maxPerHour) {
    const now = Date.now();
    if (now - log.hour > 3_600_000) {
        log.hour = now;
        log.count = 0;
    }
    if (now - log.last < secondsBetween * 1000) return true;
    if (log.count >= maxPerHour) return true;
    log.last = now;
    log.count += 1;
    return false;
}

/// The address the request came from, for the rate limit.
function clientAddress(request) {
    return request.headers.get("cf-connecting-ip") || request.headers.get("x-forwarded-for") || "unknown";
}

/// The text of a share's payload: the name, the author and the shader.
async function decodePayload(payload) {
    try {
        const bytes = Uint8Array.from(atob(payload.replace(/-/g, "+").replace(/_/g, "/")),
            (c) => c.charCodeAt(0));
        const inflated = new DecompressionStream("deflate-raw");
        const stream = new Blob([bytes]).stream().pipeThrough(inflated);
        return await new Response(stream).json();
    } catch {
        return null;
    }
}

/// The payload for a share: the same shape the app sends, deflated so it is
/// small enough to sit in a link.
async function encodePayload({ name, author, url, shader }) {
    const json = JSON.stringify({
        name: name ?? "",
        author: author ?? "",
        url: url ?? null,
        shader: shader ?? "",
    });
    const bytes = new TextEncoder().encode(json);
    const stream = new Blob([bytes]).stream().pipeThrough(new CompressionStream("deflate-raw"));
    const compressed = new Uint8Array(await new Response(stream).arrayBuffer());
    let binary = "";
    for (const byte of compressed) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function textResult(text, isError = false) {
    const result = { content: [{ type: "text", text }] };
    if (isError) result.isError = true;
    return result;
}

async function callTool(params, env, request) {
    const name = params?.name;
    const args = params?.arguments ?? {};
    switch (name) {
        case "vibescape_reference":
            return textResult(VIBESCAPE_REFERENCE);
        case "get_palette": {
            if (typeof args.name === "string" && args.name.trim() !== "") {
                const wanted = args.name.trim().toUpperCase();
                const palette = PALETTES[wanted];
                if (!palette) {
                    return textResult("There is no palette called " + wanted + ". The five are " +
                        Object.keys(PALETTES).join(", ") + ".", true);
                }
                return textResult(paletteReport(wanted, palette));
            }
            return textResult(Object.keys(PALETTES)
                .map((key) => paletteReport(key, PALETTES[key]))
                .join("\n\n"));
        }
        case "lint_vibescape": {
            if (typeof args.code !== "string" || args.code.trim() === "") {
                return textResult("Give it some code to look at.", true);
            }
            const warnings = lintVibescape(args.code);
            if (warnings.length === 0) {
                return textResult("Nothing to say — it reads the music, it accounts for the palette, and it uses the position and the time.");
            }
            return textResult("It compiles, and there are a few things worth knowing:\n\n" +
                warnings.map((warning) => "• " + warning).join("\n"));
        }
        case "get_app":
            return textResult([
                "Vibresia is a free macOS app that listens to the music playing on your Mac and draws it. No browser, no microphone permission, and it updates itself.",
                "",
                "Download: https://vibresia.com",
                "Install, in one line:",
                "",
                "    curl -fsSL https://vibresia.com/install.sh | bash",
                "",
                "It needs macOS 14.2 or later on Apple silicon.",
                "",
                "Once it is open, click “Share System Audio” and allow system audio recording when macOS asks. The audio is analysed on the Mac and never recorded or uploaded.",
            ].join("\n"));
        case "list_vibescapes": {
            const result = await env.SHARES.prepare(
                "SELECT id, name, author, created_at FROM shares WHERE is_public = 1 ORDER BY created_at DESC LIMIT 100"
            ).all();
            if (!result.results.length) {
                return textResult("The gallery is empty. Make one and share it, and it will be here.");
            }
            const lines = result.results.map((row) =>
                `• ${row.name || "Untitled"} — by ${row.author || "Minith Labs"}\n  https://vibresia.com/s/${row.id}`);
            return textResult("The public gallery:\n\n" + lines.join("\n\n"));
        }
        case "get_vibescape": {
            const id = typeof args.id === "string" ? args.id.trim() : "";
            if (!SHARE_ID_PATTERN.test(id)) {
                return textResult("That is not a share id. It is the last six characters of the link.", true);
            }
            const row = await env.SHARES.prepare(
                "SELECT payload, name, author FROM shares WHERE id = ?"
            ).bind(id).first();
            if (!row) {
                return textResult("There is no vibescape with that id.", true);
            }
            const payload = await decodePayload(row.payload);
            if (!payload) {
                return textResult("That share's code could not be read.", true);
            }
            return textResult([
                `${payload.name || row.name || "Untitled"} — by ${payload.author || row.author || "Minith Labs"}`,
                "",
                "```glsl",
                payload.shader || "",
                "```",
            ].join("\n"));
        }
        case "create_vibescape": {
            const code = typeof args.code === "string" ? args.code : "";
            const name = typeof args.name === "string" ? args.name.trim() : "";
            if (code.trim() === "") return textResult("Give it some code to draw with.", true);
            if (name === "") return textResult("Give it a name.", true);
            if (rateLimited(createLog, CREATE_SECONDS_BETWEEN, CREATE_MAX_PER_HOUR)) {
                return textResult("That is a lot of vibescapes in a short time. Try again in a moment.", true);
            }
            const payload = await encodePayload({
                name,
                author: typeof args.author === "string" ? args.author.trim() : "",
                url: null,
                shader: code,
            });
            const id = randomShareId();
            try {
                // The gallery flag is zero: a new vibescape is unlisted until
                // somebody shares it, which is a separate, deliberate act.
                await env.SHARES.prepare(
                    "INSERT INTO shares (id, payload, name, author, is_public, created_at) VALUES (?, ?, ?, ?, ?, ?)"
                ).bind(id, payload, name, typeof args.author === "string" ? args.author.trim() : "",
                    0, Date.now()).run();
            } catch (error) {
                console.log(`[mcp] could not create a vibescape: ${error}`);
                return textResult("The vibescape could not be saved. Try again.", true);
            }
            const warnings = lintVibescape(code);
            return textResult([
                `Made it: https://vibresia.com/s/${id}`,
                "",
                "That link is live — the page draws the vibescape and animates it in the browser, so it works for anybody who opens it, with or without the app.",
                "",
                warnings.length
                    ? "A few things worth knowing before you share it:\n\n" + warnings.map((w) => "• " + w).join("\n")
                    : "It looks good to me.",
                "",
                "It is not in the public gallery yet. Call `share_vibescape` with the id when you want it listed.",
            ].join("\n"));
        }
        case "share_vibescape": {
            const id = typeof args.id === "string" ? args.id.trim() : "";
            if (!SHARE_ID_PATTERN.test(id)) {
                return textResult("That is not a share id. It is the last six characters of the link.", true);
            }
            if (rateLimited(shareLog, 1, SHARE_MAX_PER_HOUR)) {
                return textResult("That is a lot of shares in a short time. Try again in a moment.", true);
            }
            const row = await env.SHARES.prepare("SELECT id FROM shares WHERE id = ?").bind(id).first();
            if (!row) return textResult("There is no vibescape with that id.", true);
            await env.SHARES.prepare("UPDATE shares SET is_public = 1 WHERE id = ?").bind(id).run();
            return textResult(
                `Listed: https://vibresia.com/s/${id}\n\nIt is in the public gallery now, at https://vibresia.com/vibescapes, where anybody can find it.`);
        }
        default:
            return textResult("There is no tool called " + name + ".", true);
    }
}

function paletteReport(name, palette) {
    return `${name} — ${palette.note}\n  shadows ${palette.shadow}, highlights ${palette.highlight}, mid ${palette.mid}\n  duotone ${palette.duotone}, saturation ${palette.saturation}, lift ${palette.lift}`;
}

/// One JSON-RPC message, answered.
async function dispatch(message, env, request) {
    const { id, method, params } = message ?? {};
    switch (method) {
        case "initialize": {
            const asked = params?.protocolVersion;
            const version = PROTOCOL_VERSIONS.includes(asked) ? asked : PROTOCOL_VERSIONS[0];
            return {
                jsonrpc: "2.0",
                id,
                result: {
                    protocolVersion: version,
                    capabilities: { tools: { listChanged: false } },
                    serverInfo: { name: "vibresia", version: "1.0.0" },
                    instructions: SERVER_INSTRUCTIONS,
                },
            };
        }
        case "notifications/initialized":
        case "notifications/cancelled":
            return null;
        case "ping":
            return { jsonrpc: "2.0", id, result: {} };
        case "tools/list":
            return { jsonrpc: "2.0", id, result: { tools: MCP_TOOLS } };
        case "tools/call":
            return {
                jsonrpc: "2.0",
                id,
                result: await callTool(params, env, request),
            };
        default:
            if (id === undefined || id === null) return null;
            return {
                jsonrpc: "2.0",
                id,
                error: { code: -32601, message: `Unknown method: ${method}` },
            };
    }
}

/// `POST /mcp` — the whole transport.
///
/// Stateless: no session, no stream, one answer per request. The spec allows
/// a server to answer with a single JSON object, and a server that holds no
/// state between requests is one that cannot be wedged by a client that
/// forgets to say goodbye.
export async function handleMcp(request, env) {
    if (request.method === "DELETE") {
        return new Response(null, { status: 204 });
    }
    if (request.method === "GET") {
        // The server-to-client stream. This server never sends anything down
        // it, so there is nothing to open.
        return new Response("This server does not send server-to-client messages.", {
            status: 405,
            headers: { allow: "POST, DELETE" },
        });
    }
    if (request.method !== "POST") {
        return new Response("Method not allowed", { status: 405, headers: { allow: "POST, DELETE" } });
    }

    let body;
    try {
        body = await request.json();
    } catch {
        return Response.json({ jsonrpc: "2.0", id: null, error: { code: -32700, message: "Parse error" } },
            { status: 400 });
    }

    const messages = Array.isArray(body) ? body : [body];
    const answers = [];
    for (const message of messages) {
        const answer = await dispatch(message, env, request);
        if (answer) answers.push(answer);
    }
    if (answers.length === 0) {
        // A notification: nothing to answer.
        return new Response(null, { status: 202 });
    }
    return Response.json(answers.length === 1 ? answers[0] : answers, {
        headers: { "mcp-protocol-version": "2025-06-18" },
    });
}
