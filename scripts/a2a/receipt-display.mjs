#!/usr/bin/env node
/**
 * Post-settle receipt printer — same shape as the Plasma USDT terminal.
 */
const amount = String(process.env.AMOUNT_ATOMIC || "20000000");
const asset = process.env.USDC_ADDR || "";
const payTo = process.env.PHIL_RECEIVE || "";
const settlement = process.env.SETTLEMENT_ADDR || "";
const txHash = process.env.TX_HASH || "";
const paymentId = process.env.PAYMENT_ID || txHash;
const payer = process.env.PAYER || "";
const chainId = process.env.CHAIN_ID || "84532";
const agentId = process.env.PAYER_AGENT_ID || "0x2d0a738d4dbfa6d5ba1dfb37e76b77fc29af7d4ac154d7655d172cb51af38ee8";
const payeeAgentId = process.env.PAYEE_AGENT_ID || "0x129319f9ad16e39a18a5788feb312cec16c08486be82a3d6bc3e398d6b05cdd3";
const network = `eip155:${chainId}`;

function b64(obj) {
  return Buffer.from(JSON.stringify(obj), "utf8").toString("base64");
}
function preview(s, n = 40) {
  return s.length <= n ? s : `${s.slice(0, n)}…`;
}

const signature = {
  x402Version: 2,
  scheme: "sohopay",
  network,
  amount,
  asset,
  payTo,
  maxTimeoutSeconds: 3600,
  extra: {
    name: "USDC",
    version: "2",
    settlementContract: settlement,
    payeeAgentId,
    agentId,
    feeBps: 0,
    closedLoop: true,
  },
  payload: {
    scheme: "sohopay",
    paymentId,
    transaction: txHash,
    settlementContract: settlement,
  },
};

const response = {
  success: true,
  transaction: txHash,
  network,
  payer,
  paymentId,
};

const body = {
  data: "a2a credit delivered to payee agent",
  status: "ok",
};

const sigB64 = b64(signature);
const resB64 = b64(response);

console.log("PAYMENT_SIGNATURE_JSON:");
console.log(JSON.stringify(signature, null, 2));
console.log(`PAYMENT_SIGNATURE_B64_PREVIEW=${preview(sigB64)}`);
console.log("PAYMENT_RESPONSE_JSON:");
console.log(JSON.stringify(response, null, 2));
console.log("RESPONSE_BODY_JSON:");
console.log(JSON.stringify(body, null, 2));
console.log(`PAYMENT_RESPONSE_B64_PREVIEW=${preview(resB64)}`);
