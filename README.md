# shaicoin

## A Digital Renaissance Powered by Verifiable Credentials (VCs)
ShaiHive is the Shaicoin mobile wallet for those who want custody over coins and culture. It pairs a fully embedded Neutrino light client with a verifiable credential wallet so users hold keys, balances, and portable digital assets in one experience. This wallet is the first step toward **Gaming Requests for Comment (GRC)**, the open specification that lets assets move between games, conventions, and metaverses with provable ownership.

## Problem Statement
Digital assets are locked to the platforms that mint them. Skins, avatars, collectibles, and achievements cannot exit their origin, so ownership dissolves when a studio turns off servers or modifies policy. Authentication depends on centralized databases, transfers are impossible, and there is no neutral registry proving who issued what. Users deserve the same rights online that they expect offline: possession, presentation, and portability.

## Wallet Features That Make It Real
- **Neutrino Light Wallet**: connects straight to Shaicoin full nodes using compact filters. Headers, filters, and UTXOs are cached on-device so balances and transactions settle without custodians.
- **Deterministic Keys + DID Roots**: mnemonic onboarding, seed derivation, and multi-format address generation (legacy, SegWit, Taproot) power both payments and DID creation. The VC stack signs with the same key material, keeping identity bound to actual ownership.
- **Credential Command Center**: the `CredentialsScreen` renders verifiable credentials as interactive trading cards. Users mint demo credentials today, flip to inspect JSON proofs, and simulate presentations, transfers, or shares—all locally.
- **Payments + Asset Flows Together**: send/receive screens, UTXO controls, fee sliders, and mempool verification sit beside credential issuance so economic actions and digital-asset actions share one trust surface.
- **Operator Controls**: settings let advanced users point the wallet at any Shaicoin node, manage banned/favorite peers, rescan from restore heights, and reset local state. Future GRC indexers and issuer registries will plug into the same surface.

## VC Usage Inside the Wallet
1. **Issue**: the app derives a DID from the user’s SegWit address, signs claims with secp256k1, and stores the VC locally with proof metadata.
2. **Inspect**: holographic cards showcase art, lore, and stats while the card back exposes indented JSON for developers or verifiers.
3. **Present**: modal flows simulate creating a Verifiable Presentation that could be scanned at a game tournament, trading floor, or AR gateway.
4. **Transfer or Share (Coming)**: UI stubs preview forthcoming flows where ownership can rotate or credentials can be packaged for cross-app exchange.

## From Wallet Actions to GRC
GRC formalizes what the wallet is prototyping:
- **Verifiable Data Registry (VDR)**: Shaicoin transactions record issuer public keys so anyone can verify asset lineage by referencing the blockchain or an indexer.
- **Off-Chain Assets, On-Chain Trust**: assets remain off-chain for speed; only ownership transitions or revocations touch the ledger. The wallet already mirrors this by storing VC payloads locally while relying on Shaicoin consensus for money.
- **Trust Triangle Network**: issuers inscribe keys, holders keep credentials in ShaiHive, verifiers query the VDR. The wallet’s presentation flows teach users how that handshake will feel.
- **Standardized Data Types**: GRC schemas (avatars, weapons, sound packs, textures, UI kits, virtual worlds, achievements) ensure that when a VC appears in ShaiHive it can also load in Unity, Unreal, or custom engines via SDK adapters.

## Trading Card Show Scenario
1. A Trading Card Issuer registers their Shaicoin public key on the VDR and mints VC-backed cards with lore, rarity, and serial numbers.
2. Collectors download ShaiHive, sync to their preferred node, and receive credentials representing each card.
3. At a physical or virtual trading card show, booths run verifier apps (powered by the GRC SDK) that scan a presentation from the wallet to confirm authenticity without exposing private data.
4. Two collectors swap assets: ShaiHive updates ownership by issuing new credentials referencing the issuer’s key, and only the ownership delta is ever notarized on-chain.
5. Later, the same cards appear inside a GRC-enabled game: the SDK reads the VC payload, enforces base stats, and lets each world add cosmetic effects or rule variations.

## Why This Sets the Stage for Cross-World Assets
- **Seamless Asset Transfers**: ShaiHive already lets users export credential JSON; future releases will stream those payloads into games, AR layers, and marketplaces using the same proofs.
- **VC Wallet Integration**: coins, DIDs, and credentials live in one secure enclave, ensuring trades at conventions or online happen under user-controlled keys.
- **Game-to-Game Interoperability**: GRC’s layered metadata keeps core stats intact while allowing each environment to add modifiers, skins, or physics quirks.
- **Marketplace + Monetization**: Shaicoin fees secure issuer registration; VC marketplaces can settle trades with on-chain payments while VC proofs protect authenticity.
- **Security**: immutability via the VDR, cryptographic presentations, and flexible revocation/rotation flows all stem from the same primitives the wallet already runs.

## Hands-On Flow
1. Install Flutter, run `flutter pub get`, then launch on iOS/Android with `flutter run`.
2. Configure node connectivity under **Settings → Node Settings** (default P2P `42069`).
3. Generate/import a mnemonic, back it up, and let the Neutrino client sync headers/filters.
4. Tap **Credentials → Demo** to mint a VC and explore its 3D visualization and raw proof block.
5. Use **Receive** to generate addresses or **Send** to broadcast transactions, proving keys stay local.
6. Export the credential JSON and verify it with prototype GRC tooling or a Shaicoin VDR indexer.

## Roadmap to GRC
1. **VDR Protocol + Indexer**: finalize inscription formats and public APIs so verifiers can trust issuer data.
2. **SDK Delivery**: ship parsers, adapters, and validation helpers for Unity, Unreal, and custom engines.
3. **Wallet Evolution**: add credential transfer, marketplace hooks, and issuer discovery directly inside ShaiHive.
4. **Pilot Programs**: partner with studios, card issuers, and event organizers to run live interoperability drills.

## Future: ShaiHive as the Home Base
ShaiHive will become the daily driver for cross-world assets. Coins, game items, avatars, achievements, event tickets, and trading cards will sit in one ledgerless vault backed by Shaicoin’s consensus. Users will walk into a game, convention, or metaverse hub and present proofs straight from the wallet. Developers will rely on the SDK to honor those proofs without reinventing security. GRC is the blueprint; ShaiHive is the cockpit.

Join us as we turn sovereign ownership into the default experience for every player, creator, collector, and builder. Shaicoin is where the digital renaissance lives.
