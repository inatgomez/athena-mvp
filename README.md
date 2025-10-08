# ATHENA: KNOWLEDGE NETWORK

**Project Status: Paused**

ATHENA is a Story Protocol-powered platform enabling authors to register books as blockchain IP assets with automated royalty distribution, multi-author collaboration, and derivative work tracking.

## Core Features

**Blockchain-Native Book Publishing**:
- Register books as IP assets with customizable PIL (Programmable IP License) terms
- Support for single and multi-author collaborations with automatic royalty splitting
- Three licensing models: Commercial Remix, Non-Commercial Social Remixing, Creative Commons Attribution

**Revenue Mechanisms**:
- Automated royalty distribution when derivative works are created
- Direct tip system for reader support
- Custom licensing fees and royalty percentages per book
- On-chain royalty payments with transparent attribution tracking

**Derivative Work Management**:
- Support for complex derivative relationships (up to 16 parent works)
- Automated licensing fee collection and distribution
  
### Smart Contracts
- **BookIPRegistrationAndManagement.sol**: Core contract handling IP registration, licensing, and royalty distribution
- **Story Protocol Integration**: Full PIL template support with custom terms
- **Multi-Author Support**: Collaborative royalty token distribution
- **Pausable & Ownable**: Security controls with whitelisted author registration

### Stack
- **Blockchain**: Story Protocol
- **Smart Contracts**: Solidity ^0.8.26
- **Frontend**: Next.js 14 with TypeScript
- **Storage**: IPFS for content files
- **Styling**: Tailwind CSS
- **Currency**: Wrapped $IP token (Story's token)

## Development Status

**Current MVP Phase**:
- ✅ Core Story Protocol integration
- ✅ Multi-author royalty distribution
- ✅ PIL template customization for books
- ✅ Derivative work registration with parent tracking
- 🔄 Frontend integration with contract functions
- 🔄 IPFS content storage implementation
- ⏳ Dispute module implementation to enforce copyright protection

## Project Goals

This is **pure R&D exploration** investigating whether blockchain-native attribution can:
- Enable sustainable knowledge creation revenue sharing
- Create transparent derivative work relationships
- Reduce unauthorized copying through attribution incentives
- Build discovery mechanisms through on-chain IP relationships

---

_This project explores technical possibilities in decentralized intellectual property management and is not intended for production use._
