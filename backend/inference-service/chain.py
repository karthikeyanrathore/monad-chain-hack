"""Monad chain access for the Inference Service: reads, unsigned user transactions,
and the service's own recordRequest transaction."""

import asyncio
import json
from pathlib import Path

from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import AsyncWeb3, Web3

ABI = json.loads((Path(__file__).parent / "InferenceTruth.abi.json").read_text())

# Monad charges gas on the limit, not gas used, so keep the buffer small.
GAS_BUFFER = 1.1


class ChainError(Exception):
    pass


def model_id(size: str) -> bytes:
    """Matches Solidity bytes32("1B")."""
    return size.encode().ljust(32, b"\0")


def request_message(model: str, nonce: int, prompt: str) -> str:
    """The text a user signs (EIP-191 personal_sign) to authorize one paid request."""
    return f"InferenceTruth request\nmodel: {model}\nnonce: {nonce}\nprompt: {prompt}"


def recover_user(model: str, nonce: int, prompt: str, signature: str) -> str:
    return Account.recover_message(encode_defunct(text=request_message(model, nonce, prompt)), signature=signature)


def request_id(user: str, nonce: int) -> bytes:
    """One id per (user, nonce), so the contract rejects a replayed signature."""
    return Web3.solidity_keccak(["address", "uint256"], [user, nonce])


def answer_hash(answer: str) -> bytes:
    return Web3.keccak(text=answer)


def _hexify(tx: dict) -> dict:
    """JSON-safe tx: wei amounts exceed JS number precision, and wallets expect hex quantities."""
    return {k: hex(v) if isinstance(v, int) else v for k, v in tx.items()}


class Chain:
    def __init__(self, rpc_url: str, contract_address: str, service_key: str):
        self.w3 = AsyncWeb3(AsyncWeb3.AsyncHTTPProvider(rpc_url))
        self.contract = self.w3.eth.contract(address=Web3.to_checksum_address(contract_address), abi=ABI)
        self.account = Account.from_key(service_key)
        self._send_lock = asyncio.Lock()  # one sender key: serialize nonces

    async def price(self, size: str) -> int:
        return await self.contract.functions.modelPrice(model_id(size)).call()

    async def deposited(self, address: str) -> int:
        return await self.contract.functions.balances(address).call()

    async def request_exists(self, rid: bytes) -> bool:
        status = (await self.contract.functions.requests(rid).call())[5]
        return status != 0

    async def account_info(self, address: str) -> dict:
        c = self.contract.functions
        return {
            "address": address,
            "deposited_wei": str(await c.balances(address).call()),
            "wallet_wei": str(await self.w3.eth.get_balance(address)),
            "stake_wei": str(await c.stakes(address).call()),
        }

    async def unsigned_tx(self, fn, sender: str, value: int = 0) -> dict:
        """Build a transaction for the user's wallet to sign and send."""
        try:
            tx = await fn.build_transaction({
                "from": sender,
                "value": value,
                "nonce": await self.w3.eth.get_transaction_count(sender, "pending"),
                "chainId": await self.w3.eth.chain_id,
            })
        except Exception as e:  # estimation reverts, e.g. insufficient funds
            raise ChainError(str(e)) from e
        tx["gas"] = int(tx["gas"] * GAS_BUFFER)
        return _hexify(tx)

    async def deposit_tx(self, sender: str, amount_wei: int) -> dict:
        return await self.unsigned_tx(self.contract.functions.deposit(), sender, amount_wei)

    async def withdraw_tx(self, sender: str, amount_wei: int) -> dict:
        return await self.unsigned_tx(self.contract.functions.withdraw(amount_wei), sender)

    async def record_request(self, rid: bytes, user: str, provider: str, size: str, ahash: bytes) -> str:
        fn = self.contract.functions.recordRequest(rid, user, provider, model_id(size), ahash)
        async with self._send_lock:
            try:
                tx = await fn.build_transaction({
                    "from": self.account.address,
                    "nonce": await self.w3.eth.get_transaction_count(self.account.address, "pending"),
                    "chainId": await self.w3.eth.chain_id,
                })
                tx["gas"] = int(tx["gas"] * GAS_BUFFER)
                signed = self.account.sign_transaction(tx)
                tx_hash = await self.w3.eth.send_raw_transaction(signed.raw_transaction)
                receipt = await self.w3.eth.wait_for_transaction_receipt(tx_hash, timeout=30)
            except Exception as e:
                raise ChainError(str(e)) from e
        if receipt["status"] != 1:
            raise ChainError(f"recordRequest reverted: {tx_hash.to_0x_hex()}")
        return tx_hash.to_0x_hex()
