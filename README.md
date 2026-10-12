# StampPass

Souvenir check-in passport DApp on BOT Chain. Create locations (events, places, memes) as collectible cards, then let anyone collect a stamp for one — accumulating a permanent, rarity-tiered passport.

## Networks

- Testnet 968 (`0x3C8`) — https://rpc.bohr.life
- Mainnet 677 (`0x2A5`) — https://rpc.botchain.ai

## Setup

```bash
npm install
cp .env.example .env   # fill PRIVATE_KEY
npm run compile
npm test
```

## Deploy

```bash
npm run deploy:testnet
# then paste address into CONTRACT_ADDRESS in frontend/index.html
```

## Frontend

Open `frontend/index.html`. Connect MetaMask, switch to BOT Testnet, browse the card feed, collect stamps, mint your own locations.

## Card rarity tiers (client-side, from `stamperCount`)

| Stampers | Tier |
| --- | --- |
| 1 | MYTHIC |
| 2–5 | LEGENDARY |
| 6–25 | EPIC |
| 26–100 | RARE |
| 101–500 | UNCOMMON |
| 501+ | COMMON |

## Fees

- `createFee` default 0.001 BOT (max 1 BOT)
- `stampFee` default 0.0005 BOT (max 0.1 BOT)
- 50% of each stamp fee routes to the location creator; the rest is platform withdrawable.
