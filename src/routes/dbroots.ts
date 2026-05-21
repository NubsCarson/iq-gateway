// /dbroots — discover every DbRoot on iqlabs in one call.
//
// Uses getProgramAccounts with a memcmp filter on the Anchor DbRoot
// discriminator so only DbRoot accounts come back (a small set: one per dApp),
// not the millions of other PDAs the program owns.
//
// Cached 30 min. DbRoots are near-static (new dApp launch or a table
// registration is the only thing that mutates them), so a long TTL is fine.

import { Hono } from "hono";
import { Connection, PublicKey } from "@solana/web3.js";
import { BorshAccountsCoder } from "@coral-xyz/anchor";
import bs58 from "bs58";
import { contract, utils } from "@iqlabs-official/solana-sdk";
import { MemoryCache } from "../cache";

export const dbrootsRouter = new Hono();

const PROGRAM_ID = new PublicKey(contract.DEFAULT_ANCHOR_PROGRAM_ID);
const accountCoder = new BorshAccountsCoder(contract.IQ_IDL);
// IDL-derived 8-byte tag every DbRoot account stores at offset 0. Using the
// coder (not a hardcoded array) keeps this resilient if the program is ever
// redeployed under a different program/account name.
const DBROOT_DISCRIMINATOR = accountCoder.accountDiscriminator("DbRoot");

const rpc = new Connection(
  process.env.SOLANA_RPC_ENDPOINT || "https://api.mainnet-beta.solana.com",
);

/** One table hint as stored in db_root.table_seeds / global_table_seeds,
 *  with the table PDA pre-derived so clients only need a string compare.
 *
 *  Derivation mirrors the SDK's toSeedBytes: a human label is keccak256'd,
 *  while an already-hashed 64-hex hint is used as the seed verbatim. The
 *  resulting seed feeds getTablePda(dbRootPda, seed). */
interface TableHint {
  /** utf-8 view if the bytes are printable, else null. */
  label: string | null;
  /** hex of the raw hint bytes — always present. */
  hex: string;
  /** the derived Table PDA (base58), or null if derivation failed. */
  tablePda: string | null;
}

interface DbRootEntry {
  pda: string;
  /** utf-8 view of db_root.id, or null when the id bytes aren't printable. */
  id: string | null;
  /** hex of the raw id bytes — stable across all dApps. */
  idHex: string;
  creator: string | null;
  /** create_table permission. empty = anyone may create. */
  tableCreators: string[];
  /** create_ext / private-table permission. empty = anyone. */
  extCreators: string[];
  /** db_root.table_seeds, raw. */
  tableSeeds: TableHint[];
  /** db_root.global_table_seeds, raw. */
  globalTableSeeds: TableHint[];
}

interface DbRootsPayload {
  dbroots: DbRootEntry[];
  fetchedAt: number;
  count: number;
}

const cache = new MemoryCache<string>(1);
const TTL_MS = 30 * 60 * 1000;
const CACHE_KEY = "dbroots:all";
let inflight: Promise<DbRootsPayload> | null = null;

function toBuffer(v: unknown): Buffer {
  if (Buffer.isBuffer(v)) return v;
  if (v instanceof Uint8Array) return Buffer.from(v);
  if (Array.isArray(v)) return Buffer.from(v as number[]);
  if (v && typeof v === "object" && Array.isArray((v as { data?: number[] }).data)) {
    return Buffer.from((v as { data: number[] }).data);
  }
  return Buffer.alloc(0);
}

// Treat tab/newline/space + printable ASCII as "displayable". Most dApps use
// kebab-case ASCII for their db_root id; raw 32-byte seeds will fail this.
function isPrintableUtf8(buf: Buffer): boolean {
  if (buf.length === 0) return false;
  for (const b of buf) {
    if (b === 0x09 || b === 0x0a || b === 0x0d) continue;
    if (b < 0x20 || b > 0x7e) return false;
  }
  return true;
}

function toHint(dbRootPda: PublicKey, v: unknown): TableHint {
  const buf = toBuffer(v);
  const printable = isPrintableUtf8(buf);
  const label = printable ? buf.toString("utf8") : null;
  const hex = buf.toString("hex");

  // Reproduce the SDK derivation: a printable label gets keccak256'd by
  // toSeedBytes; a 64-hex hint is taken as raw seed bytes. Either way we pass
  // the original hint string into toSeedBytes so its HEX_64 branch decides.
  let tablePda: string | null = null;
  try {
    const seedInput = label ?? hex;
    const seed = utils.toSeedBytes(seedInput);
    tablePda = contract.getTablePda(dbRootPda, seed, PROGRAM_ID).toBase58();
  } catch {
    tablePda = null;
  }

  return { label, hex, tablePda };
}

function toPubkeyList(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v.map((pk) => {
    try {
      return pk instanceof PublicKey ? pk.toBase58() : new PublicKey(pk as never).toBase58();
    } catch {
      return "";
    }
  }).filter(Boolean);
}

function decodeDbRoot(pda: PublicKey, raw: Buffer): DbRootEntry {
  // BorshAccountsCoder.decode strips the 8-byte discriminator before parsing.
  const decoded = accountCoder.decode("DbRoot", raw) as Record<string, unknown>;
  const tableSeeds = (decoded.table_seeds ?? decoded.tableSeeds ?? []) as unknown[];
  const globalTableSeeds = (decoded.global_table_seeds ?? decoded.globalTableSeeds ?? []) as unknown[];
  const creator = decoded.creator as PublicKey | undefined;

  const idBuf = toBuffer(decoded.id);
  const idPrintable = isPrintableUtf8(idBuf);
  return {
    pda: pda.toBase58(),
    id: idPrintable ? idBuf.toString("utf8") : null,
    idHex: idBuf.toString("hex"),
    creator: creator ? new PublicKey(creator).toBase58() : null,
    tableCreators: toPubkeyList(decoded.table_creators ?? decoded.tableCreators),
    extCreators: toPubkeyList(decoded.ext_creators ?? decoded.extCreators),
    tableSeeds: tableSeeds.map((s) => toHint(pda, s)),
    globalTableSeeds: globalTableSeeds.map((s) => toHint(pda, s)),
  };
}

async function fetchAllDbRoots(): Promise<DbRootsPayload> {
  const accounts = await rpc.getProgramAccounts(PROGRAM_ID, {
    filters: [
      {
        memcmp: {
          offset: 0,
          bytes: bs58.encode(DBROOT_DISCRIMINATOR),
        },
      },
    ],
  });

  const dbroots: DbRootEntry[] = [];
  for (const { pubkey, account } of accounts) {
    try {
      dbroots.push(decodeDbRoot(pubkey, account.data));
    } catch (e) {
      console.warn(`[dbroots] failed to decode ${pubkey.toBase58()}: ${e instanceof Error ? e.message : e}`);
    }
  }

  // Sort for stable output across calls: named dApps first (by id), then the
  // rest by pda.
  dbroots.sort((a, b) => {
    if (a.id && b.id) return a.id.localeCompare(b.id);
    if (a.id) return -1;
    if (b.id) return 1;
    return a.pda.localeCompare(b.pda);
  });

  return {
    dbroots,
    fetchedAt: Date.now(),
    count: dbroots.length,
  };
}

dbrootsRouter.get("/", async (c) => {
  const cached = cache.get(CACHE_KEY);
  if (cached) return c.json(JSON.parse(cached));

  // Dedup concurrent cold-cache requests so we only hit RPC once.
  if (!inflight) {
    inflight = (async () => {
      try {
        return await fetchAllDbRoots();
      } finally {
        inflight = null;
      }
    })();
  }

  try {
    const payload = await inflight;
    cache.set(CACHE_KEY, JSON.stringify(payload), TTL_MS);
    return c.json(payload);
  } catch (e) {
    console.error("[dbroots] failed:", e instanceof Error ? e.message : e);
    return c.json({ error: "failed to read DbRoots" }, 500);
  }
});
