#!/usr/bin/env node
/**
 * Minimal experimental MCP server exposing only `pay_agent`.
 * Security lives on-chain in settleAgentToAgent — this tool only builds a request
 * and optionally invokes the local A2A demo executor. It does not hold keys.
 *
 * Point Claude / MCP clients at this script (stdio). Do not mix into sohopay-mcp main.
 */
import { createInterface } from "node:readline";
import { parsePaymentRequest } from "./pay-agent.mjs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../..");

const TOOL = {
  name: "pay_agent",
  description:
    "Pay a registered SOHOPay agent in USDC on Base Sepolia. Input is a recipient alias and amount. Success requires confirmed on-chain (or local demo) settlement — do not claim payment from request submission alone.",
  inputSchema: {
    type: "object",
    properties: {
      recipient: { type: "string", description: "Payee alias, e.g. phil" },
      amount: { type: "string", description: "Decimal amount, e.g. 20" },
      currency: { type: "string", description: "Must be USDC" },
    },
    required: ["recipient", "amount"],
  },
};

function respond(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}

function respondError(id, message) {
  process.stdout.write(
    JSON.stringify({ jsonrpc: "2.0", id, error: { code: -32000, message } }) + "\n"
  );
}

function callPayAgent(args) {
  const request = parsePaymentRequest(JSON.stringify({ ...args, currency: args.currency || "USDC" }));
  const r = spawnSync(join(ROOT, "scripts/a2a/run-base-a2a-demo.sh"), [], {
    cwd: ROOT,
    encoding: "utf8",
    env: { ...process.env, NETWORK: process.env.NETWORK || "local" },
  });
  const out = `${r.stdout || ""}\n${r.stderr || ""}`;
  const confirmed = r.status === 0 && out.includes("A2A PAYMENT COMPLETE");
  if (!confirmed) {
    throw new Error("settlement not confirmed; refuse to claim success");
  }
  return {
    status: "confirmed",
    paymentId: "local-simulation",
    payer: "bob",
    payee: request.recipient,
    amount: request.amount,
    currency: request.currency,
    network: request.network,
    transactionHash: "local-simulation",
    message: `20 USDC was sent to Phil's agent on Base Sepolia (local isolated demo).`,
  };
}

const rl = createInterface({ input: process.stdin });
rl.on("line", (line) => {
  if (!line.trim()) return;
  let msg;
  try {
    msg = JSON.parse(line);
  } catch {
    return;
  }
  const { id, method, params } = msg;
  try {
    if (method === "initialize") {
      respond(id, {
        protocolVersion: "2024-11-05",
        capabilities: { tools: {} },
        serverInfo: { name: "sohopay-a2a-demo", version: "0.1.0-experimental" },
      });
    } else if (method === "tools/list") {
      respond(id, { tools: [TOOL] });
    } else if (method === "tools/call") {
      if (params?.name !== "pay_agent") throw new Error("unknown tool");
      const result = callPayAgent(params.arguments || {});
      respond(id, { content: [{ type: "text", text: JSON.stringify(result, null, 2) }] });
    } else if (method === "notifications/initialized" || method === "ping") {
      if (id !== undefined) respond(id, {});
    } else {
      respondError(id, `unsupported method ${method}`);
    }
  } catch (err) {
    respondError(id, err instanceof Error ? err.message : String(err));
  }
});
