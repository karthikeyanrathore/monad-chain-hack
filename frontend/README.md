# Frontend

Next.js chat UI for Inference Truth. Users connect a browser wallet, deposit MON, pick a model (1B or 3B) and chat. Every prompt is signed in the wallet and paid from the deposit on Monad testnet.

## Run
```bash
npm install
npm run dev          # http://localhost:3000
```
It needs the Inference Service on port 8000 (`backend/scripts/05-start-service.sh`) and the Verification Service on port 9000 (`05b-start-verifier.sh`).
Requests to `/backend/*` and `/verifier/*` are proxied to them (override with `BACKEND_URL` / `VERIFIER_URL`).

## Use
1. **Connect wallet** (top right). It switches to or adds Monad testnet (chain 10143).
   - **Any wallet can connect.** Each user has their own deposit and signs their own prompts, so nobody can spend anyone else's MON.
   - Switching accounts in MetaMask switches the dashboard to that account's deposit.
   - To lock the app to one address (private demo), set `NEXT_PUBLIC_USER_ADDRESS` in `.env.local`, or run `LOCK_TO_ADDRESS=0x… ./deploy-frontend.sh`.
2. **Deposit:** enter an amount and click Deposit. The backend builds the transaction, and your wallet signs and sends it.
3. **Chat:** pick `llama 1B` or `llama 3B`, then send.
   - Your wallet asks you to sign the request (free, no gas).
   - The answer shows the price paid, a link to the on-chain record, and then the verification result: "✓ verified · machine paid", linking to the payout transaction, or "✗ failed · refunded".
4. **Withdraw:** takes unused MON back out of the contract.

## Backend endpoints used
| Endpoint | Used for |
|---|---|
| `GET /models` | Model prices in the picker |
| `GET /account/{address}` | Deposit balance in the header |
| `POST /tx/deposit`, `POST /tx/withdraw` | Unsigned transactions; the wallet signs and sends them |
| `POST /infer` | Signed, paid prompt |

## Code
- `lib/api.ts`: backend calls and the exact message users sign.
- `lib/wallet.ts`: wallet connect, Monad network switch, `personal_sign`, sending transactions.
- `app/components/WalletBar.tsx`: connect, deposit, withdraw and balance.
- `app/components/ChatClient.tsx`: chat. Signs each prompt, then calls `/infer`.
