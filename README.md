# XCV Perpetuals Protocol

A simple cross-chain-ready **Perpetual Futures Trading Protocol** focused on a single ETH/USDC market. It supports:

- Leverage trading (1x–10x)
- Long & short positions
- Liquidity provisioning with LP tokens
- Reserve-based fund locking
- Accurate PnL calculation
- Liquidation based on collateral ratio
- Chainlink-ready for oracle and cross-chain integrations

---

## 🧠 Architecture Overview

```text
            ┌────────────────────────┐
            │     Price Oracle       │◄─────── Chainlink Data Feeds
            └────────────────────────┘
                       ▲
                       │
                       ▼
┌────────────┐   ┌─────────────┐   ┌────────────────────────┐
│  Liquidity │   │ Perp Market │   │      Trader UI         │
│   Pool     │◄─►│ (ETH/USDC)  │◄─►│  (deposit, trade, etc) │
└────────────┘   └─────────────┘   └────────────────────────┘
                       ▲
                       │
                 Reserve / Release


Chainlink Price feed:

Ethereum Mainnet ETH/USD: 0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419

Sepolia Testnet ETH/USD: 0x694AA1769357215DE4FAC081bf1f309aDC325306