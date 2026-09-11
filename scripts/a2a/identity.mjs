#!/usr/bin/env node
/**
 * Demo identity + @handle directory.
 * Handle → agentId / merchantId → receive or payout. Not a security boundary.
 */
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "../..");
const SEED_PATH = join(ROOT, "scripts/a2a/recipients.json");
const CREDIT_LIMIT = 20;
const PER_TX_CAP = 20;

export function sohopayHome() {
  return process.env.SOHOPAY_HOME || process.env.HOME || ROOT;
}

export function identityPath() {
  return join(sohopayHome(), ".sohopay", "a2a-demo-identity.json");
}

function normalize(s) {
  return String(s || "")
    .trim()
    .toLowerCase()
    .replace(/['’]/g, "")
    .replace(/^@/, "")
    .replace(/\s+/g, " ");
}

function handleize(s) {
  return normalize(s).replace(/[^a-z0-9_]/g, "");
}

export function demoAddress(seed) {
  const hex = createHash("sha256").update(String(seed)).digest("hex").slice(0, 40);
  return `0x${hex}`;
}

export function loadSeed() {
  return JSON.parse(readFileSync(SEED_PATH, "utf8"));
}

export function loadUser() {
  const p = identityPath();
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, "utf8"));
}

export function saveUser(user) {
  const p = identityPath();
  mkdirSync(dirname(p), { recursive: true, mode: 0o700 });
  writeFileSync(p, `${JSON.stringify(user, null, 2)}\n`, { mode: 0o600 });
  return user;
}

export function resetUser() {
  const p = identityPath();
  if (existsSync(p)) rmSync(p);
}

export function directoryEntries() {
  const seed = loadSeed();
  const user = loadUser();
  const out = { ...seed };
  if (user?.handle) {
    out[user.handle] = {
      label: user.label || `${user.name} Agent`,
      handle: user.handle,
      alias: user.alias || [user.handle, user.name, `${user.name}'s agent`],
      agentIdPreimage: user.agentIdPreimage,
      role: "payer",
      receiveAddress: user.receiveAddress,
      localUser: true,
    };
  }
  return out;
}

export function suggestHandle(name) {
  const parts = String(name || "")
    .trim()
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
  const first = parts[0] || "agent";
  const last = parts.length > 1 ? parts[parts.length - 1] : "";
  const candidates = [first, last ? `${first}${last[0]}` : "", last ? `${first}_${last}` : "", `${first}agent`].filter(
    Boolean
  );
  const taken = takenHandles();
  for (const c of candidates) {
    const h = handleize(c);
    if (h.length >= 2 && !taken.has(h)) return h;
  }
  let i = 2;
  const base = handleize(first) || "agent";
  while (taken.has(`${base}${i}`)) i += 1;
  return `${base}${i}`;
}

function takenHandles(except = "") {
  const taken = new Set();
  const skip = handleize(except);
  for (const [id, rec] of Object.entries(directoryEntries())) {
    const handles = [id, rec.handle, ...(rec.alias || [])].map(handleize).filter(Boolean);
    for (const h of handles) {
      if (h !== skip) taken.add(h);
    }
  }
  return taken;
}

export function assertHandleAvailable(handle, except = "") {
  const h = handleize(handle);
  if (!/^[a-z][a-z0-9_]{1,19}$/.test(h)) {
    throw new Error("handle must be 2–20 chars: letters, numbers, underscore (start with a letter)");
  }
  if (takenHandles(except).has(h)) throw new Error(`@${h} is taken. Try another handle.`);
  return h;
}

export function normalizePhone(raw) {
  const digits = String(raw || "").replace(/\D/g, "");
  if (digits.length < 10 || digits.length > 15) {
    throw new Error("enter a valid phone number (10–15 digits)");
  }
  return digits;
}

export function maskPhone(phone) {
  const d = String(phone || "");
  if (d.length < 4) return "••••";
  return `••••${d.slice(-4)}`;
}

export function parseRepayMethod(raw) {
  const n = String(raw || "")
    .trim()
    .toLowerCase();
  if (n === "a" || n === "1" || n === "wallet" || n === "address") return "wallet";
  if (n === "b" || n === "2" || n === "card" || n === "bank" || n === "bank card") return "card";
  throw new Error("choose A (wallet) or B (bank card)");
}

export function normalizeWallet(raw) {
  const a = String(raw || "").trim();
  if (!/^0x[a-fA-F0-9]{40}$/.test(a)) {
    throw new Error("wallet must be a 0x address (42 chars). Example: 0xDe20913Abf62FE97838AF397a4f4F2BD665E94f9");
  }
  return a;
}

export function normalizeCardFields({ number, cvc, exp }) {
  const digits = String(number || "").replace(/\s|-/g, "");
  if (!/^\d{13,19}$/.test(digits)) {
    throw new Error("card number must be 13–19 digits. Example: 4242424242424242");
  }
  const cvcDigits = String(cvc || "").replace(/\D/g, "");
  if (!/^\d{3,4}$/.test(cvcDigits)) {
    throw new Error("CVC must be 3 or 4 digits. Example: 123");
  }
  const expRaw = String(exp || "").trim();
  const m = expRaw.match(/^(\d{1,2})\s*\/\s*(\d{2})$/);
  if (!m) throw new Error("expiration must be MM/YY. Example: 12/28");
  const month = Number(m[1]);
  if (month < 1 || month > 12) throw new Error("expiration month must be 01–12. Example: 12/28");
  const expNorm = `${String(month).padStart(2, "0")}/${m[2]}`;
  return {
    repayMethod: "card",
    repayCardLast4: digits.slice(-4),
    repayCardExp: expNorm,
    repayLabel: `card ••••${digits.slice(-4)} exp ${expNorm}`,
  };
}

export function claimIdentity({ name, phone, handle, repayMethod, repayWallet, cardNumber, cvc, exp }) {
  const trimmed = String(name || "").trim();
  if (trimmed.length < 2) throw new Error("name is required");
  const phoneDigits = normalizePhone(phone);
  const h = assertHandleAvailable(handle || suggestHandle(trimmed));
  const method = parseRepayMethod(repayMethod || "wallet");
  let repay = { repayMethod: method, repayLabel: "" };
  if (method === "wallet") {
    const addr = normalizeWallet(repayWallet);
    repay = { repayMethod: "wallet", repayWallet: addr, repayLabel: `wallet ${addr}` };
  } else {
    repay = normalizeCardFields({ number: cardNumber, cvc, exp });
  }
  const user = {
    name: trimmed,
    phone: phoneDigits,
    handle: h,
    label: `${trimmed.split(/\s+/)[0]} Agent`,
    agentIdPreimage: `${h.toUpperCase()}_AGENT`,
    receiveAddress: demoAddress(`sohopay-receive:${h}`),
    creditLimit: CREDIT_LIMIT,
    perTxCap: PER_TX_CAP,
    outstanding: 0,
    createdAt: new Date().toISOString(),
    ...repay,
  };
  return saveUser(user);
}

export function availableCredit(user = loadUser()) {
  if (!user) return 0;
  return Math.max(0, Number(user.creditLimit) - Number(user.outstanding || 0));
}

export function debitCredit(amount) {
  const user = loadUser();
  if (!user) throw new Error("no identity — run sohopay to onboard");
  const n = Number(amount);
  if (!(n > 0)) throw new Error("amount must be positive");
  if (n > Number(user.perTxCap)) throw new Error(`above per-transaction cap (${n} > ${user.perTxCap})`);
  const next = Number(user.outstanding || 0) + n;
  if (next > Number(user.creditLimit)) {
    throw new Error(`insufficient SohoPay credit (${availableCredit(user)} USDC left on a $${user.creditLimit} line)`);
  }
  user.outstanding = next;
  saveUser(user);
  return user;
}

function recordMatches(id, rec, key, exactHandleOnly) {
  const handle = handleize(rec.handle || id);
  if (exactHandleOnly) return handle === key || handleize(id) === key;
  const aliases = [id, rec.handle, rec.label, ...(rec.alias || [])].map(normalize);
  return handle === key || aliases.includes(key);
}

export function resolveRecipient(raw) {
  const text = String(raw || "").trim();
  const exactHandleOnly = text.startsWith("@") || Boolean(text.match(/^@[a-zA-Z][a-zA-Z0-9_]*$/));
  const key = normalize(text);
  const addrMatch = text.match(/0x[a-fA-F0-9]{40}/);
  const entries = Object.entries(directoryEntries());

  if (addrMatch) {
    const addr = addrMatch[0];
    for (const [id, rec] of entries) {
      const receive = rec.receiveAddress || rec.payout || "";
      if (receive && receive.toLowerCase() === addr.toLowerCase()) {
        return packRecipient(id, rec, "receiveAddress");
      }
    }
    return {
      id: "unknown",
      handle: "",
      label: addr,
      role: "address",
      agentIdPreimage: "",
      merchantIdPreimage: "",
      receiveAddress: addr,
      matchedBy: "rawAddress",
      registeredAgent: false,
      registeredMerchant: false,
    };
  }

  const hits = [];
  for (const [id, rec] of entries) {
    if (recordMatches(id, rec, key, exactHandleOnly)) hits.push([id, rec]);
  }
  if (hits.length === 1) return packRecipient(hits[0][0], hits[0][1], exactHandleOnly ? "handle" : "alias");
  if (hits.length > 1) {
    const handles = hits.map(([id, rec]) => `@${rec.handle || id}`).join(", ");
    throw new Error(`ambiguous name "${text}". Pay a unique handle: ${handles}`);
  }
  const known = Object.entries(directoryEntries())
    .map(([id, rec]) => `@${rec.handle || id}`)
    .join(", ");
  throw new Error(
    `unknown handle "${text}". This testnet demo settles on-chain to @phil only. Known: ${known || "@phil"}`
  );
}

function packRecipient(id, rec, matchedBy) {
  const role = rec.role || "payee";
  const registeredMerchant = role === "merchant";
  const registeredAgent = !registeredMerchant && role !== "address";
  return {
    id,
    handle: rec.handle || id,
    label: rec.label || id,
    role,
    agentIdPreimage: rec.agentIdPreimage || "",
    merchantIdPreimage: rec.merchantIdPreimage || "",
    receiveAddress: rec.receiveAddress || rec.payout || "",
    matchedBy,
    registeredAgent,
    registeredMerchant,
    localUser: Boolean(rec.localUser),
  };
}

export function parsePaymentRequest(input) {
  const text = String(input || "").trim();
  if (!text) throw new Error("empty payment request");

  let parsed;
  if (text.startsWith("{")) {
    parsed = JSON.parse(text);
  } else {
    const addr = (text.match(/0x[a-fA-F0-9]{40}/) || [])[0];
    const amountMatch = text.match(/\$?\s*([0-9]+(?:\.[0-9]+)?)/);
    const currencyMatch = text.match(/\b(usdc|usdt|usd)\b/i);
    let recipient = "";

    const agentForm = text.match(/pay\s+(.+?)(?:'s|’s)?\s+agent\s+/i);
    const toForm = text.match(/\bto\s+(@?[a-zA-Z0-9_.-]+|0x[a-fA-F0-9]{40})\s*$/i);
    const handleAmt = text.match(/^pay\s+(@[a-zA-Z][a-zA-Z0-9_]*)\s+/i);
    const payNameAmt = text.match(/^pay\s+([a-zA-Z][a-zA-Z0-9_-]*)\s+\$?\s*[0-9]/i);

    if (addr) recipient = addr;
    else if (handleAmt) recipient = handleAmt[1];
    else if (agentForm) recipient = agentForm[1].replace(/['’]s$/i, "").trim();
    else if (toForm) recipient = toForm[1].replace(/\b(usdc|usdt|usd)\b/gi, "").trim();
    else if (payNameAmt) recipient = payNameAmt[1];
    else recipient = "phil";

    if (!amountMatch) throw new Error("missing amount. Try: pay @phil 20");
    parsed = {
      recipient,
      amount: amountMatch[1],
      currency: (currencyMatch?.[1] || "USDC").toUpperCase() === "USD" ? "USDC" : (currencyMatch?.[1] || "USDC").toUpperCase(),
    };
  }

  const recipient = resolveRecipient(parsed.recipient);
  const amount = String(parsed.amount);
  let currency = String(parsed.currency || "USDC").toUpperCase();
  if (currency === "USD") currency = "USDC";
  const network = String(parsed.network || "base-sepolia");
  if (network !== "base-sepolia") throw new Error("A2A demo only supports base-sepolia");

  return {
    recipient: recipient.id,
    handle: recipient.handle ? `@${recipient.handle}` : "",
    amount,
    currency,
    network,
    agentIdPreimage: recipient.agentIdPreimage,
    merchantIdPreimage: recipient.merchantIdPreimage,
    label: recipient.label,
    receiveAddress: recipient.receiveAddress || "",
    matchedBy: recipient.matchedBy,
    role: recipient.role,
    registeredAgent: recipient.registeredAgent,
    registeredMerchant: recipient.registeredMerchant,
    localUser: recipient.localUser,
  };
}

function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const arg = rest.join(" ");
  try {
    switch (cmd) {
      case "whoami":
        console.log(JSON.stringify(loadUser() || {}));
        break;
      case "phone":
        console.log(normalizePhone(arg));
        break;
      case "repay-method":
        console.log(parseRepayMethod(arg));
        break;
      case "wallet":
        console.log(normalizeWallet(arg));
        break;
      case "card":
        console.log(JSON.stringify(normalizeCardFields(JSON.parse(arg || "{}"))));
        break;
      case "suggest":
        console.log(suggestHandle(arg));
        break;
      case "available":
        assertHandleAvailable(arg);
        console.log("ok");
        break;
      case "claim":
        console.log(JSON.stringify(claimIdentity(JSON.parse(arg || "{}")), null, 2));
        break;
      case "parse":
        console.log(JSON.stringify(parsePaymentRequest(arg), null, 2));
        break;
      case "debit":
        console.log(JSON.stringify(debitCredit(arg), null, 2));
        break;
      case "credit-left":
        console.log(String(availableCredit()));
        break;
      case "reset":
        resetUser();
        console.log("reset");
        break;
      case "path":
        console.log(identityPath());
        break;
      case "directory":
        console.log(
          JSON.stringify(
            Object.entries(directoryEntries()).map(([id, rec]) => ({
              id,
              handle: `@${rec.handle || id}`,
              role: rec.role,
              label: rec.label,
            })),
            null,
            2
          )
        );
        break;
      default:
        console.error("usage: identity.mjs whoami|suggest|claim|parse|debit|reset|directory");
        process.exit(1);
    }
  } catch (err) {
    console.error(err.message || err);
    process.exit(1);
  }
}

const isMain = process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1];
if (isMain) main();
