#!/usr/bin/env node
/**
 * Thin natural-language / structured A2A request layer.
 * Does NOT authorize payments. On-chain settleAgentToAgent remains the source of truth.
 *
 * Usage:
 *   node scripts/a2a/pay-agent.mjs "Pay Phil's agent $20"
 *   node scripts/a2a/pay-agent.mjs "pay @phil 20"
 *   node scripts/a2a/pay-agent.mjs "pay 20 usdc to @acme"
 */
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { parsePaymentRequest } from "./identity.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../..");

function executeLocalDemo() {
  const env = { ...process.env, NETWORK: process.env.NETWORK || "local" };
  const r = spawnSync(join(ROOT, "scripts/a2a/run-base-a2a-demo.sh"), [], {
    cwd: ROOT,
    env,
    encoding: "utf8",
  });
  if (r.status !== 0) {
    return {
      status: "failed",
      error: (r.stderr || r.stdout || "executor failed").slice(-2000),
    };
  }
  const out = r.stdout || "";
  const confirmed = out.includes("A2A PAYMENT COMPLETE");
  return {
    status: confirmed ? "confirmed" : "failed",
    payer: "local-user",
    payee: "phil",
    amount: "20",
    currency: "USDC",
    network: "base-sepolia",
    transactionHash: confirmed ? "local-simulation" : "",
    outputTail: out.slice(-1500),
  };
}

function main() {
  const args = process.argv.slice(2);
  const execute = args.includes("--execute");
  const jsonIdx = args.indexOf("--json");
  const input =
    jsonIdx >= 0
      ? args[jsonIdx + 1]
      : args.filter((a) => a !== "--execute" && a !== "--json").join(" ") ||
        "Pay Phil's agent $20";
  const request = parsePaymentRequest(input);
  if (!execute) {
    console.log(JSON.stringify(request, null, 2));
    return;
  }
  if (!request.registeredAgent || request.recipient !== "phil" || Number(request.amount) !== 20) {
    console.error(
      JSON.stringify(
        {
          status: "failed",
          error:
            "Live isolated demo currently settles the 20 USDC Bob → Phil fixture. Use demo mode in the sohopay shell for other payees.",
          request,
        },
        null,
        2
      )
    );
    process.exit(1);
  }
  const result = executeLocalDemo();
  if (result.status !== "confirmed") {
    console.error(JSON.stringify(result, null, 2));
    process.exit(1);
  }
  console.log(
    JSON.stringify(
      {
        status: result.status,
        payer: result.payer,
        payee: result.payee,
        amount: result.amount,
        currency: result.currency,
        network: result.network,
        transactionHash: result.transactionHash,
        request,
      },
      null,
      2
    )
  );
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) main();
