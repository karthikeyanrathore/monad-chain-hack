// Minimal injected-wallet (MetaMask etc.) helpers for Monad testnet. The backend never sees keys:
// the wallet signs prompts and sends the deposit/withdraw transactions the backend builds.

import type { UnsignedTx } from "./api";

interface Eip1193 {
  request(args: { method: string; params?: unknown[] }): Promise<unknown>;
  on?(event: string, handler: (...args: unknown[]) => void): void;
  removeListener?(event: string, handler: (...args: unknown[]) => void): void;
}

declare global {
  interface Window {
    ethereum?: Eip1193;
  }
}

export const MONAD_TESTNET = {
  chainId: "0x279f", // 10143
  chainName: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: ["https://testnet-rpc.monad.xyz"],
  blockExplorerUrls: ["https://testnet.monadvision.com"],
};

export const explorerTx = (hash: string) => `${MONAD_TESTNET.blockExplorerUrls[0]}/tx/${hash}`;

/**
 * Any wallet can connect by default: each user signs their own prompts and pays from their own deposit.
 * Set NEXT_PUBLIC_USER_ADDRESS to lock the app to a single address (e.g. for a private demo).
 */
export const USER_ADDRESS = process.env.NEXT_PUBLIC_USER_ADDRESS ?? "";
const ALLOWED_ADDRESS = USER_ADDRESS.toLowerCase();

export const isAllowed = (address: string | null): address is string =>
  !!address && (!ALLOWED_ADDRESS || address.toLowerCase() === ALLOWED_ADDRESS);

export const notAllowedMessage = (address: string) =>
  `MetaMask is on ${address.slice(0, 6)}…${address.slice(-4)}. This app only accepts ${USER_ADDRESS}.`;

function eth(): Eip1193 {
  if (typeof window === "undefined" || !window.ethereum) {
    throw new Error("No wallet found. Install MetaMask (or another browser wallet).");
  }
  return window.ethereum;
}

/** Ask for an account, accept only the allowed user wallet, and make sure the wallet is on Monad testnet. */
export async function connect(): Promise<string> {
  const accounts = (await eth().request({ method: "eth_requestAccounts" })) as string[];
  const address = accounts.find(isAllowed);
  if (!address) throw new Error(notAllowedMessage(accounts[0] ?? "no account"));
  await ensureMonad();
  return address;
}

export async function ensureMonad(): Promise<void> {
  const chainId = (await eth().request({ method: "eth_chainId" })) as string;
  if (chainId === MONAD_TESTNET.chainId) return;
  try {
    await eth().request({ method: "wallet_switchEthereumChain", params: [{ chainId: MONAD_TESTNET.chainId }] });
  } catch (e) {
    // 4902: chain not added to the wallet yet
    if ((e as { code?: number }).code !== 4902) throw e;
    await eth().request({ method: "wallet_addEthereumChain", params: [MONAD_TESTNET] });
  }
}

/** EIP-191 personal_sign of a UTF-8 message. */
export async function signMessage(address: string, message: string): Promise<string> {
  const hex = "0x" + Array.from(new TextEncoder().encode(message), (b) => b.toString(16).padStart(2, "0")).join("");
  return (await eth().request({ method: "personal_sign", params: [hex, address] })) as string;
}

/** Send a backend-built transaction from the wallet and wait until it is mined. */
export async function sendAndWait(tx: UnsignedTx): Promise<string> {
  await ensureMonad();
  // The wallet manages nonce and chain itself; keep the backend's tight gas limit (Monad charges the limit).
  const { from, to, data, value, gas, maxFeePerGas, maxPriorityFeePerGas } = tx;
  const hash = (await eth().request({
    method: "eth_sendTransaction",
    params: [{ from, to, data, value, gas, maxFeePerGas, maxPriorityFeePerGas }],
  })) as string;
  for (let i = 0; i < 60; i++) {
    const receipt = (await eth().request({ method: "eth_getTransactionReceipt", params: [hash] })) as {
      status: string;
    } | null;
    if (receipt) {
      if (receipt.status !== "0x1") throw new Error(`Transaction failed: ${explorerTx(hash)}`);
      return hash;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`Transaction not confirmed yet: ${explorerTx(hash)}`);
}

export function onAccountsChanged(handler: (address: string | null) => void): () => void {
  const eth = typeof window !== "undefined" ? window.ethereum : undefined;
  if (!eth?.on) return () => {};
  const h = (...args: unknown[]) => handler((args[0] as string[])[0] ?? null);
  eth.on("accountsChanged", h);
  return () => eth.removeListener?.("accountsChanged", h);
}
